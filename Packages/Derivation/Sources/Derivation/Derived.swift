//
//  Derived.swift
//  Derivation
//
//  The five kinds of derived value. Each is built from the JSON its engine produced, in the
//  reference layout: keys in byte order, no whitespace, lowercase hex, and `recipe`
//  omitted when empty for Password, Secret and SymmetricKey but present for the key pairs.
//  `toJson()` returns that text unchanged because it is a displayed output format.
//

import Foundation

/// Decodes one engine JSON document into its fields, or reports what was wrong with it.
private func decodeFields<T: Decodable>(_ type: T.Type, from json: String) throws(DerivationError) -> T {
    do {
        return try JSONDecoder().decode(type, from: Data(json.utf8))
    } catch {
        throw .internalError("the engine produced unreadable JSON: \(error)")
    }
}

private func hexField(_ hex: String, named name: String) throws(DerivationError) -> Data {
    guard let data = Data(hex: hex) else { throw .internalError("the engine produced a non-hex \(name)") }
    return data
}

public struct Password: Sendable, Equatable {
    public let password: String
    public let recipe: Recipe
    private let json: String

    private struct Fields: Decodable { let password: String }

    public static func derive(seed: String, recipe: String) throws(DerivationError) -> Password {
        let parsed = try Recipe(json: recipe, type: .password)
        let json = try defaultEngine.derive(.password, seed: seed, recipe: recipe)
        return Password(password: try decodeFields(Fields.self, from: json).password, recipe: parsed, json: json)
    }

    public func toJson() -> String { json }
}

public struct Secret: Sendable, Equatable {
    public let bytes: Data
    public let recipe: Recipe
    private let json: String

    private struct Fields: Decodable { let secretBytes: String }

    public static func derive(seed: String, recipe: String) throws(DerivationError) -> Secret {
        let parsed = try Recipe(json: recipe, type: .secret)
        let json = try defaultEngine.derive(.secret, seed: seed, recipe: recipe)
        let fields = try decodeFields(Fields.self, from: json)
        return Secret(bytes: try hexField(fields.secretBytes, named: "secretBytes"), recipe: parsed, json: json)
    }

    public func toJson() -> String { json }
}

public struct SymmetricKey: Sendable, Equatable {
    public let keyBytes: Data
    public let recipe: Recipe
    private let json: String

    private struct Fields: Decodable { let keyBytes: String }

    public static func derive(seed: String, recipe: String) throws(DerivationError) -> SymmetricKey {
        let parsed = try Recipe(json: recipe, type: .symmetricKey)
        let json = try defaultEngine.derive(.symmetricKey, seed: seed, recipe: recipe)
        let fields = try decodeFields(Fields.self, from: json)
        return SymmetricKey(keyBytes: try hexField(fields.keyBytes, named: "keyBytes"), recipe: parsed, json: json)
    }

    public func toJson() -> String { json }
}

public struct UnsealingKey: Sendable, Equatable {
    public let unsealingKeyBytes: Data
    public let sealingKeyBytes: Data
    public let recipe: Recipe
    private let json: String

    private struct Fields: Decodable { let unsealingKeyBytes: String; let sealingKeyBytes: String }

    public static func derive(seed: String, recipe: String) throws(DerivationError) -> UnsealingKey {
        let parsed = try Recipe(json: recipe, type: .unsealingKey)
        let json = try defaultEngine.derive(.unsealingKey, seed: seed, recipe: recipe)
        let fields = try decodeFields(Fields.self, from: json)
        return UnsealingKey(
            unsealingKeyBytes: try hexField(fields.unsealingKeyBytes, named: "unsealingKeyBytes"),
            sealingKeyBytes: try hexField(fields.sealingKeyBytes, named: "sealingKeyBytes"),
            recipe: parsed,
            json: json
        )
    }

    public func toJson() -> String { json }
}

public struct SigningKey: Sendable, Equatable {
    /// The Ed25519 seed followed by the public key, 64 bytes, as libsodium lays it out.
    public let signingKeyBytes: Data
    public let recipe: Recipe
    private let json: String

    public var verificationKeyBytes: Data { signingKeyBytes.suffix(32) }

    private struct Fields: Decodable { let signingKeyBytes: String }

    public static func derive(seed: String, recipe: String) throws(DerivationError) -> SigningKey {
        let parsed = try Recipe(json: recipe, type: .signingKey)
        let json = try defaultEngine.derive(.signingKey, seed: seed, recipe: recipe)
        let fields = try decodeFields(Fields.self, from: json)
        let bytes = try hexField(fields.signingKeyBytes, named: "signingKeyBytes")
        guard bytes.count == 64 else { throw .internalError("the engine produced a \(bytes.count)-byte signing key") }
        return SigningKey(signingKeyBytes: bytes, recipe: parsed, json: json)
    }

    public func toJson() -> String { json }
}
