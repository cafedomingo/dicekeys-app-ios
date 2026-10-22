//
//  Derived.swift
//  Derivation
//

import Foundation

/// An Ed25519 key from a recipe.
public struct SigningKey: Sendable, Equatable {
    /// The Ed25519 seed followed by the public key, 64 bytes.
    public let signingKeyBytes: Data

    public static let publicKeyLength = 32

    public var verificationKeyBytes: Data { Data(signingKeyBytes.suffix(Self.publicKeyLength)) }

    public init(seed: String, recipe: KeyRecipe) {
        let bytes = Engine.bytes(seed: seed, type: .ed25519, recipe: recipe.json, length: Engine.keyLength)
        signingKeyBytes = Data(Engine.ed25519(seed: bytes))
    }
}

/// An X25519 key pair from a recipe.
public struct UnsealingKey: Sendable, Equatable {
    public let unsealingKeyBytes: Data
    public let sealingKeyBytes: Data

    public init(seed: String, recipe: KeyRecipe) {
        let scalar = Engine.bytes(seed: seed, type: .x25519, recipe: recipe.json, length: Engine.keyLength)
        unsealingKeyBytes = Data(scalar)
        sealingKeyBytes = Data(Engine.x25519PublicKey(scalar: scalar))
    }
}

/// 32 raw bytes from a recipe, for a key made from bytes: a wallet's BIP39 entropy.
public enum Secret {
    public static func bytes(seed: String, recipe: KeyRecipe, type: DerivableType) -> Data {
        Data(Engine.bytes(seed: seed, type: type, recipe: recipe.json, length: Engine.keyLength))
    }
}

/// A passphrase recipe's passphrase: one 8-byte block per character or word.
public enum Passphrase {
    /// Nil for a recipe of any other kind, which has no style.
    public static func derive(seed: String, recipe: KeyRecipe) -> String? {
        guard let style = recipe.style else { return nil }
        let length = style.entryCount * PasswordFormatter.bytesPerEntry
        return PasswordFormatter.passphrase(
            from: Engine.bytes(seed: seed, type: .passphrase, recipe: recipe.json, length: length), style: style)
    }
}

/// A DiceKey's id: 16 bytes as unpadded URL-safe base64. One-way: it reveals nothing about
/// the dice. It is its own type with no recipe, so its info is the type name alone.
public enum DiceKeyID {
    private static let length = 16

    public static func derive(seed: String) -> String {
        Data(Engine.bytes(seed: seed, type: .diceKeyID, recipe: "", length: length)).base64URLEncodedString
    }
}
