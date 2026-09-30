//
//  Derivables.swift
//  DiceKeys
//
//  Created by Stuart Schechter on 2020/12/03.
//

import Foundation
import Derivation

func getRecipeJson(purpose: String, sequenceNumber: Int = 1, lengthInChars: Int = -1, lengthInBytes: Int = -1) -> String {
    RecipeJsonValue.object(
        [RecipeJsonField(name: "purpose", value: .text(purpose))]
        + optionalRecipeFields(sequenceNumber: sequenceNumber, lengthInChars: lengthInChars, lengthInBytes: lengthInBytes)
    ).canonicalText
}

/// The fields a user can set on any recipe. Each is written only when it differs from the
/// default, because a recipe with `"#":1` derives a different secret from one without it.
private func optionalRecipeFields(sequenceNumber: Int, lengthInChars: Int?, lengthInBytes: Int?) -> [RecipeJsonField] {
    var fields: [RecipeJsonField] = []
    if let lengthInChars, lengthInChars > 1 {
        fields.append(RecipeJsonField(name: "lengthInChars", value: .int(lengthInChars)))
    }
    if let lengthInBytes, lengthInBytes > 1 {
        fields.append(RecipeJsonField(name: "lengthInBytes", value: .int(lengthInBytes)))
    }
    if sequenceNumber > 1 {
        fields.append(RecipeJsonField(name: "#", value: .int(sequenceNumber)))
    }
    return fields
}

struct DerivationRecipe: Identifiable, Codable, Equatable {
    static let rebuildSkipJsonProperties = ["#", "lengthInChars", "lengthInBytes"]

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
        let typeSuffix = switch template.type {
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
        return try JSONDecoder().decode([DerivationRecipe].self, from: json.data(using: .utf8)! )
    }

    static func listToJson(_ derivables: [DerivationRecipe]) throws -> String { String(decoding: try JSONEncoder().encode(derivables), as: UTF8.self) }
}

extension DerivationRecipe {
    /// Throws when the recipe is not valid, which a hand-edited raw JSON recipe or one
    /// saved before validation existed can be; the message says what is wrong.
    func derivedValue(diceKey: DiceKey) throws -> any DerivedValue {
        let seed = diceKey.toSeed()
        switch type {
        case .password:
            return DerivedValuePassword(password: try Password.derive(seed: seed, recipe: recipe))
        case .secret:
            let lengthInBytes = lengthInBytes()
            return DerivedValueSecret(secret: try Secret.derive(seed: seed, recipe: recipe), showBIP39: lengthInBytes == nil || lengthInBytes == 32)
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
        case ("pgp", .signingKey): return .OpenPGPPrivateKey
        case ("ssh", .signingKey): return .OpenSSHPrivateKey
        case ("wallet", .secret) where derivedValue.views.contains(.BIP39): return .BIP39
        default: return derivedValue.views.first ?? .JSON
        }
    }

    /// The recipe's fields, or none when the stored text is not a JSON object. Recipes saved
    /// by earlier versions were not validated, so this never throws.
    var fields: [RecipeJsonField] {
        (try? RecipeJsonParser.parseObject(recipe)) ?? []
    }

    func purpose() -> String? {
        guard case .string(let quoted) = fields.first(where: { $0.name == "purpose" })?.value else { return nil }
        return try? RecipeJsonParser.decodeString(quoted: quoted)
    }

    func lengthInChars() -> Int? {
        integerField("lengthInChars")
    }

    func lengthInBytes() -> Int? {
        integerField("lengthInBytes")
    }

    private func integerField(_ name: String) -> Int? {
        guard case .number(let text) = fields.first(where: { $0.name == name })?.value else { return nil }
        return Int(text)
    }
}
