//
//  Engine.swift
//  Derivation
//

import CryptoKit

/// The derivation: HKDF over BLAKE2b for the bytes and CryptoKit for the curves. Every
/// `derive` on the derived types comes here, and each type lays out its own JSON.
enum Engine {
    /// The recipe's text, not its parsed form, salts the derivation, so a byte of whitespace
    /// or a reordered key yields a different secret.
    static func secret(seed: String, type: DerivableType, recipe: Recipe) -> [UInt8] {
        let info = Array(type.rawValue.utf8) + Array(recipe.json.utf8)
        return recipe.hashFunction.derive(seed: Array(seed.utf8), info: info, outputLength: recipe.lengthInBytes)
    }

    /// libsodium's crypto_box_seed_keypair hashes the seed with SHA-512 and keeps the first
    /// 32 bytes as the scalar, unclamped; the curve multiplication clamps.
    static func x25519(secret: [UInt8]) -> (scalar: [UInt8], publicKey: [UInt8]) {
        let scalar = Array(SHA512.hash(data: secret).prefix(32))
        do {
            let key = try Curve25519.KeyAgreement.PrivateKey(rawRepresentation: scalar)
            return (scalar, Array(key.publicKey.rawRepresentation))
        } catch {
            preconditionFailure("X25519 rejected a 32-byte scalar: \(error)")
        }
    }

    /// The derived bytes are the Ed25519 seed; libsodium's secret key is that seed followed
    /// by the public key.
    static func ed25519(seed: [UInt8]) -> [UInt8] {
        do {
            let key = try Curve25519.Signing.PrivateKey(rawRepresentation: seed)
            return seed + Array(key.publicKey.rawRepresentation)
        } catch {
            preconditionFailure("Ed25519 rejected a 32-byte seed: \(error)")
        }
    }
}
