//
//  DerivedKey.swift
//  KeyFormats
//

import Derivation
import Foundation

/// One algorithm's key of a catalog entry, encoded the way the tool it feeds expects.
public struct AlgorithmKey: Equatable, Sendable {
    public let type: DerivableType
    /// What goes where the key is trusted: an `authorized_keys` line, a WireGuard peer's
    /// key, an age recipient. Nil for a passphrase or a wallet.
    public let publicKey: String?
    /// A short form of the public key to compare by eye. Nil when there is no public key,
    /// and for age's post-quantum recipient.
    public let fingerprint: String?
    /// The private key file or string, the passphrase, or the recovery phrase.
    public let secret: String

    public init(type: DerivableType, publicKey: String?, fingerprint: String?, secret: String) {
        self.type = type
        self.publicKey = publicKey
        self.fingerprint = fingerprint
        self.secret = secret
    }
}

/// A catalog entry's keys: one per algorithm of its recipe's kind.
public struct DerivedKey: Equatable, Sendable {
    public let recipe: KeyRecipe
    /// One per algorithm of the recipe's kind, in `KeyKind.algorithms` order.
    public let algorithms: [AlgorithmKey]

    /// Each algorithm's public key by its type's raw value, which is how the catalog stores
    /// them. Empty for a passphrase or a wallet.
    public var publicKeys: [String: String] {
        Dictionary(uniqueKeysWithValues: algorithms.compactMap { key in key.publicKey.map { (key.type.rawValue, $0) } })
    }

    /// Every recipe the app builds is valid, so derivation cannot fail.
    public static func derive(seed: String, recipe: KeyRecipe) -> DerivedKey {
        DerivedKey(
            recipe: recipe,
            algorithms: recipe.kind.algorithms.map { algorithm(seed: seed, recipe: recipe, type: $0) })
    }

    private static func algorithm(seed: String, recipe: KeyRecipe, type: DerivableType) -> AlgorithmKey {
        switch (recipe.kind, type) {
        case (.ssh, .ed25519):
            let key = Ed25519Key(seed: seed, recipe: recipe)
            return AlgorithmKey(
                type: type,
                publicKey: OpenSSH.publicKeyLine(key, comment: recipe.name ?? ""),
                fingerprint: OpenSSH.fingerprint(key),
                secret: OpenSSH.privateKeyPEM(key, comment: recipe.name ?? ""))
        case (.wireguard, .x25519):
            let key = X25519KeyPair(seed: seed, recipe: recipe)
            let publicKey = WireGuard.publicKey(key)
            return AlgorithmKey(
                type: type, publicKey: publicKey, fingerprint: publicKey, secret: WireGuard.privateKey(key))
        case (.age, .x25519):
            let key = X25519KeyPair(seed: seed, recipe: recipe)
            let publicKey = Age.recipient(key)
            return AlgorithmKey(type: type, publicKey: publicKey, fingerprint: publicKey, secret: Age.identity(key))
        case (.age, .mlkem768x25519):
            do {
                return try Age.postQuantum(seed: Secret.bytes(seed: seed, recipe: recipe, type: type))
            } catch {
                preconditionFailure("CryptoKit rejected 32 bytes of X-Wing seed: \(error)")
            }
        case (.passphrase, .passphrase):
            guard let passphrase = Passphrase.derive(seed: seed, recipe: recipe) else {
                preconditionFailure("A passphrase recipe always has a style")
            }
            return AlgorithmKey(type: type, publicKey: nil, fingerprint: nil, secret: passphrase)
        case (.wallet, .bip39):
            do {
                let entropy = Secret.bytes(seed: seed, recipe: recipe, type: type)
                return AlgorithmKey(
                    type: type, publicKey: nil, fingerprint: nil, secret: try BIP39.mnemonic(entropy: entropy))
            } catch {
                preconditionFailure("BIP39 rejected 32 bytes of entropy: \(error)")
            }
        default:
            preconditionFailure("A \(recipe.kind) key has no \(type) algorithm")
        }
    }
}
