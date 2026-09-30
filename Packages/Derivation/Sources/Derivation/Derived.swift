//
//  Derived.swift
//  Derivation
//

import Foundation

public struct Password: Sendable, Equatable {
    public let password: String
    public let recipe: Recipe

    public static func derive(seed: String, recipe: String) throws(DerivationError) -> Password {
        let parsed = try Recipe(json: recipe, type: .password)
        let secret = Engine.secret(seed: seed, type: .password, recipe: parsed)
        let password = PasswordFormatter.password(from: secret, wordList: parsed.wordList, lengthInChars: parsed.lengthInChars)
        return Password(password: password, recipe: parsed)
    }

    public func toJson() -> String {
        ReferenceJSON.object([(key: "password", value: password)] + ReferenceJSON.recipeIfPresent(recipe))
    }
}

public struct Secret: Sendable, Equatable {
    public let bytes: Data
    public let recipe: Recipe

    public static func derive(seed: String, recipe: String) throws(DerivationError) -> Secret {
        let parsed = try Recipe(json: recipe, type: .secret)
        return Secret(bytes: Data(Engine.secret(seed: seed, type: .secret, recipe: parsed)), recipe: parsed)
    }

    public func toJson() -> String {
        ReferenceJSON.object([(key: "secretBytes", value: ReferenceJSON.hex(bytes))] + ReferenceJSON.recipeIfPresent(recipe))
    }
}

public struct SymmetricKey: Sendable, Equatable {
    public let keyBytes: Data
    public let recipe: Recipe

    public static func derive(seed: String, recipe: String) throws(DerivationError) -> SymmetricKey {
        let parsed = try Recipe(json: recipe, type: .symmetricKey)
        return SymmetricKey(keyBytes: Data(Engine.secret(seed: seed, type: .symmetricKey, recipe: parsed)), recipe: parsed)
    }

    public func toJson() -> String {
        ReferenceJSON.object([(key: "keyBytes", value: ReferenceJSON.hex(keyBytes))] + ReferenceJSON.recipeIfPresent(recipe))
    }
}

public struct UnsealingKey: Sendable, Equatable {
    public let unsealingKeyBytes: Data
    public let sealingKeyBytes: Data
    public let recipe: Recipe

    public static func derive(seed: String, recipe: String) throws(DerivationError) -> UnsealingKey {
        let parsed = try Recipe(json: recipe, type: .unsealingKey)
        let pair = Engine.x25519(secret: Engine.secret(seed: seed, type: .unsealingKey, recipe: parsed))
        return UnsealingKey(unsealingKeyBytes: Data(pair.scalar), sealingKeyBytes: Data(pair.publicKey), recipe: parsed)
    }

    public func toJson() -> String {
        ReferenceJSON.object([
            (key: "recipe", value: recipe.json),
            (key: "sealingKeyBytes", value: ReferenceJSON.hex(sealingKeyBytes)),
            (key: "unsealingKeyBytes", value: ReferenceJSON.hex(unsealingKeyBytes))
        ])
    }
}

public struct SigningKey: Sendable, Equatable {
    /// The Ed25519 seed followed by the public key, 64 bytes.
    public let signingKeyBytes: Data
    public let recipe: Recipe

    public var verificationKeyBytes: Data { Data(signingKeyBytes.suffix(32)) }

    public static func derive(seed: String, recipe: String) throws(DerivationError) -> SigningKey {
        let parsed = try Recipe(json: recipe, type: .signingKey)
        let bytes = Engine.ed25519(seed: Engine.secret(seed: seed, type: .signingKey, recipe: parsed))
        return SigningKey(signingKeyBytes: Data(bytes), recipe: parsed)
    }

    public func toJson() -> String {
        ReferenceJSON.object([
            (key: "recipe", value: recipe.json),
            (key: "signingKeyBytes", value: ReferenceJSON.hex(signingKeyBytes))
        ])
    }
}
