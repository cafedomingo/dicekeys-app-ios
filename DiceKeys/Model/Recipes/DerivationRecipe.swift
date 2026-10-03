//
//  Derivables.swift
//  DiceKeys
//

import Derivation
import Foundation

func getRecipeJson(purpose: String, sequenceNumber: Int = 1, lengthInBytes: Int? = nil) -> String {
    RecipeJsonValue.object(
        [RecipeJsonField(name: Recipe.purposeField, value: .text(purpose))]
            + optionalRecipeFields(sequenceNumber: sequenceNumber, lengthInChars: nil, lengthInBytes: lengthInBytes)
    ).canonicalText
}

func getRecipeJson(purpose: String, sequenceNumber: Int, choices: PasswordRecipeChoices) -> String {
    RecipeJsonValue.object(
        [RecipeJsonField(name: Recipe.purposeField, value: .text(purpose))] + choices.fields
            + optionalRecipeFields(sequenceNumber: sequenceNumber, lengthInChars: nil, lengthInBytes: nil)
    ).canonicalText
}

/// The fields a user can set on any recipe. Each is written only when it differs from the
/// default, because a recipe with `"#":1` derives a different secret from one without it.
private func optionalRecipeFields(sequenceNumber: Int, lengthInChars: Int?, lengthInBytes: Int?) -> [RecipeJsonField] {
    var fields: [RecipeJsonField] = []
    if let lengthInChars, lengthInChars > 1 {
        fields.append(RecipeJsonField(name: Recipe.lengthInCharsField, value: .int(lengthInChars)))
    }
    if let lengthInBytes, lengthInBytes > 1 {
        fields.append(RecipeJsonField(name: Recipe.lengthInBytesField, value: .int(lengthInBytes)))
    }
    if sequenceNumber > 1 {
        fields.append(RecipeJsonField(name: Recipe.sequenceNumberField, value: .int(sequenceNumber)))
    }
    return fields
}

struct DerivationRecipe: Identifiable, Codable, Equatable {
    static let rebuildSkipJsonProperties = [
        Recipe.sequenceNumberField, Recipe.lengthInCharsField, Recipe.lengthInBytesField
    ]
    /// A wallet seed phrase is offered only for 32-byte secrets, the 24 words wallets expect.
    private static let bip39SecretLength = 32

    let type: DerivableType
    let name: String
    let recipe: String

    var id: String { "\(type):\(name):\(recipe)" }

    init(type: DerivableType, name: String, recipe: String) {
        self.type = type
        self.name = name
        self.recipe = recipe
    }

    init(template: DerivationRecipe, sequenceNumber: Int, lengthInChars: Int? = nil, lengthInBytes: Int? = nil) {
        self.type = template.type
        let typeSuffix =
            switch template.type {
            case .password: " Password"
            case .symmetricKey: " Key"
            case .unsealingKey: " Key Pair"
            case .secret, .signingKey: ""
            }
        let sequenceSuffix = sequenceNumber == 1 ? "" : " (\(String(sequenceNumber)))"
        self.name = template.name + typeSuffix + sequenceSuffix

        let kept = template.fields.filter { !DerivationRecipe.rebuildSkipJsonProperties.contains($0.name) }
        let added = optionalRecipeFields(
            sequenceNumber: sequenceNumber,
            lengthInChars: template.type == .password ? lengthInChars : nil,
            lengthInBytes: template.type == .secret ? lengthInBytes : nil
        )
        self.recipe = RecipeJsonValue.object(kept + added).canonicalText
    }

    static func listFromJson(_ json: String) throws -> [DerivationRecipe]? {
        return try JSONDecoder().decode([DerivationRecipe].self, from: json.data(using: .utf8)!)
    }

    static func listToJson(_ derivables: [DerivationRecipe]) throws -> String {
        String(decoding: try JSONEncoder().encode(derivables), as: UTF8.self)
    }
}

extension DerivationRecipe {
    /// Throws when the recipe is invalid, as a hand-edited raw JSON recipe can be.
    func derivedValue(diceKey: DiceKey) throws -> any DerivedValue {
        let seed = diceKey.toSeed()
        switch type {
        case .password:
            return DerivedValuePassword(password: try Password.derive(seed: seed, recipe: recipe))
        case .secret:
            let lengthInBytes = lengthInBytes()
            return DerivedValueSecret(
                secret: try Secret.derive(seed: seed, recipe: recipe),
                showBIP39: (lengthInBytes ?? Recipe.defaultLengthInBytes) == Self.bip39SecretLength)
        case .signingKey:
            return DerivedValueSigningKey(signingKey: try SigningKey.derive(seed: seed, recipe: recipe))
        case .symmetricKey:
            return DerivedValueSymmetricKey(symmetricKey: try SymmetricKey.derive(seed: seed, recipe: recipe))
        case .unsealingKey:
            return DerivedValueUnsealingKey(unsealingKey: try UnsealingKey.derive(seed: seed, recipe: recipe))
        }
    }

    /// The output format this recipe's users expect first: OpenPGP or OpenSSH for those
    /// signing keys, BIP39 for a wallet seed, and otherwise the value's primary format
    /// (the password itself, for passwords).
    func defaultOutputFormat(for derivedValue: any DerivedValue) -> DerivedValueView {
        switch (purpose(), type) {
        case ("pgp", .signingKey): return .openPGPPrivateKey
        case ("ssh", .signingKey): return .openSSHPrivateKey
        case ("wallet", .secret) where derivedValue.views.contains(.bip39): return .bip39
        default: return derivedValue.views.first ?? .json
        }
    }

    /// The recipe's fields, or none when the text is not a JSON object; never throws.
    var fields: [RecipeJsonField] {
        (try? RecipeJsonParser.parseObject(recipe)) ?? []
    }

    func purpose() -> String? {
        guard case .string(let quoted) = fields.first(where: { $0.name == Recipe.purposeField })?.value else {
            return nil
        }
        return try? RecipeJsonParser.decodeString(quoted: quoted)
    }

    func lengthInChars() -> Int? {
        integerField(Recipe.lengthInCharsField)
    }

    func lengthInBytes() -> Int? {
        integerField(Recipe.lengthInBytesField)
    }

    private func integerField(_ name: String) -> Int? {
        guard case .number(let text) = fields.first(where: { $0.name == name })?.value else { return nil }
        return Int(text)
    }
}
