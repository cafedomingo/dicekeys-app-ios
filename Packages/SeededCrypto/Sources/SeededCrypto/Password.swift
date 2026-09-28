//
//  Password.swift
//  SeededCrypto
//

import Foundation
import SeededCryptoNative

/// A password derived from a seed and a recipe.
public struct Password: Sendable, Hashable {
    /// The canonical JSON form produced by the library (`{"password":..., "recipe":...}`).
    public let json: String
    public let password: String
    public let recipe: String

    private struct Fields: Decodable {
        let password: String
        let recipe: String?
    }

    init(nativeJson json: String) throws {
        let fields = try Native.decode(Fields.self, from: json)
        self.json = json
        self.password = fields.password
        self.recipe = fields.recipe ?? ""
    }

    public static func deriveFromSeed(withSeedString seedString: String, recipe: String) throws -> Password {
        try Password(nativeJson: Native.string { out, err in dkc_password_derive(seedString, recipe, out, err) })
    }

    public static func from(json: String) throws -> Password {
        try Password(nativeJson: Native.string { out, err in dkc_password_from_json(json, out, err) })
    }

    public func toJson() -> String { json }
}
