//
//  Derivables.swift
//  DiceKeys
//
//  Created by Stuart Schechter on 2020/12/03.
//

import Foundation
import SeededCrypto

func getRecipeJson(hosts: [String], sequenceNumber: Int = 1, lengthInChars: Int = -1, lengthInBytes: Int = -1) -> String {
    RecipeJsonValue.object(
        [RecipeJsonField(name: "allow", value: .array(hosts.sorted().map { .text($0) }))]
        + optionalRecipeFields(sequenceNumber: sequenceNumber, lengthInChars: lengthInChars, lengthInBytes: lengthInBytes)
    ).canonicalText
}

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

    let type: SeededCryptoRecipeType
    let name: String
    let recipe: String

    var id: String { "\(type):\(name):\(recipe)" }

    init(type: SeededCryptoRecipeType, name: String, recipe: String) {
        self.type = type
        self.name = name
        self.recipe = recipe
    }

    init(template: DerivationRecipe, sequenceNumber: Int, lengthInChars: Int? = nil, lengthInBytes: Int? = nil) {
        self.type = template.type
        let typeSuffix = template.type == .Password ? " Password" : template.type == .SymmetricKey ? " Key" : template.type == .UnsealingKey ? " Key Pair" : ""
        let sequenceSuffix = sequenceNumber == 1 ? "" : " (\(String(sequenceNumber)))"
        self.name = template.name + typeSuffix + sequenceSuffix

        let kept = template.fields.filter { !DerivationRecipe.rebuildSkipJsonProperties.contains($0.name) }
        let added = optionalRecipeFields(
            sequenceNumber: sequenceNumber,
            lengthInChars: template.type == .Password ? lengthInChars : nil,
            lengthInBytes: template.type == .Secret ? lengthInBytes : nil
        )
        self.recipe = RecipeJsonValue.object(kept + added).canonicalText
    }

    static func listFromJson(_ json: String) throws -> [DerivationRecipe]? {
        return try JSONDecoder().decode([DerivationRecipe].self, from: json.data(using: .utf8)! )
    }

    static func listToJson(_ derivables: [DerivationRecipe]) throws -> String { String(decoding: try JSONEncoder().encode(derivables), as: UTF8.self) }
}

extension DerivationRecipe {
    /// Throws when SeededCrypto rejects the recipe, which a hand-edited raw JSON recipe can be.
    func derivedValue(diceKey: DiceKey) throws -> any DerivedValue {
        let seed = diceKey.toSeed()
        let recipe = self.recipe

        switch self.type {
        case .Password:
            return DerivedValuePassword(password: try Password.deriveFromSeed(withSeedString: seed, recipe: recipe))
        case .Secret:
            let lengthInBytes = self.lengthInBytes()
            return DerivedValueSecret(secret: try Secret.deriveFromSeed(withSeedString: seed, recipe: recipe), showBIP39: (lengthInBytes == nil || lengthInBytes == 32))
        case .SigningKey:
            return DerivedValueSigningKey(signingKey: try SigningKey.deriveFromSeed(withSeedString: seed, recipe: recipe))
        case .SymmetricKey:
            return DerivedValueSymmetricKey(symmetricKey: try SymmetricKey.deriveFromSeed(withSeedString: seed, recipe: recipe))
        case .UnsealingKey:
            return DerivedValueUnsealingKey(unsealingKey: try UnsealingKey.deriveFromSeed(withSeedString: seed, recipe: recipe))
        }
    }

    /// The output format this recipe's users expect first: OpenPGP or OpenSSH for those
    /// signing keys, BIP39 for a wallet seed, and otherwise the value's primary format
    /// (the password itself, for passwords).
    func defaultOutputFormat(for derivedValue: any DerivedValue) -> DerivedValueView {
        switch (purpose(), type) {
        case ("pgp", .SigningKey): return .OpenPGPPrivateKey
        case ("ssh", .SigningKey): return .OpenSSHPrivateKey
        case ("wallet", .Secret) where derivedValue.views.contains(.BIP39): return .BIP39
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
