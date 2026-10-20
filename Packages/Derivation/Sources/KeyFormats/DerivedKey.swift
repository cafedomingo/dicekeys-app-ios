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

    /// Every template is a valid recipe, so derivation cannot fail.
    public static func derive(seed: String, recipe: KeyRecipe) -> DerivedKey {
        do {
            switch recipe.kind {
            case .ssh:
                let key = try SigningKey.derive(seed: seed, recipe: recipe.json)
                return DerivedKey(
                    recipe: recipe,
                    publicKey: OpenSSH.publicKeyLine(key, comment: recipe.name),
                    fingerprint: OpenSSH.fingerprint(key),
                    secret: OpenSSH.privateKeyPEM(key, comment: recipe.name))
            case .wireguard:
                let key = try UnsealingKey.derive(seed: seed, recipe: recipe.json)
                let publicKey = WireGuard.publicKey(key)
                return DerivedKey(
                    recipe: recipe, publicKey: publicKey, fingerprint: publicKey,
                    secret: WireGuard.privateKey(key))
            case .age:
                let key = try UnsealingKey.derive(seed: seed, recipe: recipe.json)
                let publicKey = Age.recipient(key)
                return DerivedKey(
                    recipe: recipe, publicKey: publicKey, fingerprint: publicKey, secret: Age.identity(key))
            case .passphrase:
                let password = try Password.derive(seed: seed, recipe: recipe.json)
                return DerivedKey(recipe: recipe, publicKey: nil, fingerprint: nil, secret: password.password)
            case .wallet:
                let secret = try Secret.derive(seed: seed, recipe: recipe.json)
                return DerivedKey(
                    recipe: recipe, publicKey: nil, fingerprint: nil, secret: try BIP39.mnemonic(entropy: secret.bytes))
            }
        } catch {
            preconditionFailure("A key recipe template failed to derive: \(error)")
        }
    }
}
