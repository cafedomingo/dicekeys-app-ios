//
//  Derived.swift
//  Derivation
//

import Foundation

/// An Ed25519 key from a recipe.
public struct Ed25519Key: Sendable, Equatable {
    /// The 32-byte Ed25519 seed.
    public let seed: Data
    public let publicKey: Data

    public init(seed: String, recipe: KeyRecipe) {
        let bytes = Engine.bytes(seed: seed, type: .ed25519, recipe: recipe.json, length: Engine.keyLength)
        self.seed = Data(bytes)
        publicKey = Data(Engine.ed25519PublicKey(seed: bytes))
    }
}

/// An X25519 key pair from a recipe.
public struct X25519KeyPair: Sendable, Equatable {
    public let privateKey: Data
    public let publicKey: Data

    public init(seed: String, recipe: KeyRecipe) {
        let scalar = Engine.bytes(seed: seed, type: .x25519, recipe: recipe.json, length: Engine.keyLength)
        privateKey = Data(scalar)
        publicKey = Data(Engine.x25519PublicKey(scalar: scalar))
    }
}

/// 32 raw bytes from a recipe, for a key made from bytes: a wallet's BIP39 entropy or an age
/// key's X-Wing seed.
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
