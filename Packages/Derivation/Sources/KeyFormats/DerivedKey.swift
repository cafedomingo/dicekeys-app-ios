//
//  DerivedKey.swift
//  KeyFormats
//

import Derivation
import Foundation

/// A catalog entry's key, encoded the way the tool it feeds expects.
public struct DerivedKey: Equatable, Sendable {
    public let recipe: KeyRecipe
    /// What goes where the key is trusted: an `authorized_keys` line, a WireGuard peer's
    /// key, an age recipient. Nil for a passphrase or a wallet.
    public let publicKey: String?
    /// A short form of the public key to compare by eye. Nil when there is no public key.
    public let fingerprint: String?
    /// The private key file or string, the passphrase, or the recovery phrase.
    public let secret: String

    /// Every recipe the app builds is valid, so derivation cannot fail.
    public static func derive(seed: String, recipe: KeyRecipe) -> DerivedKey {
        switch recipe.kind {
        case .ssh:
            let key = Ed25519Key(seed: seed, recipe: recipe)
            return DerivedKey(
                recipe: recipe,
                publicKey: OpenSSH.publicKeyLine(key, comment: recipe.name),
                fingerprint: OpenSSH.fingerprint(key),
                secret: OpenSSH.privateKeyPEM(key, comment: recipe.name))
        case .wireguard:
            let key = X25519KeyPair(seed: seed, recipe: recipe)
            let publicKey = WireGuard.publicKey(key)
            return DerivedKey(
                recipe: recipe, publicKey: publicKey, fingerprint: publicKey, secret: WireGuard.privateKey(key))
        case .age:
            let key = X25519KeyPair(seed: seed, recipe: recipe)
            let publicKey = Age.recipient(key)
            return DerivedKey(
                recipe: recipe, publicKey: publicKey, fingerprint: publicKey, secret: Age.identity(key))
        case .passphrase:
            guard let passphrase = Passphrase.derive(seed: seed, recipe: recipe) else {
                preconditionFailure("A passphrase recipe always has a style")
            }
            return DerivedKey(recipe: recipe, publicKey: nil, fingerprint: nil, secret: passphrase)
        case .wallet:
            let entropy = Secret.bytes(seed: seed, recipe: recipe, type: .bip39)
            do {
                return DerivedKey(
                    recipe: recipe, publicKey: nil, fingerprint: nil, secret: try BIP39.mnemonic(entropy: entropy))
            } catch {
                preconditionFailure("BIP39 rejected 32 bytes of entropy: \(error)")
            }
        }
    }
}
