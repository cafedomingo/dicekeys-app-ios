//
//  Engine.swift
//  Derivation
//

import CryptoKit

/// HKDF over BLAKE2b for the bytes, CryptoKit for the curves.
enum Engine {
    /// The recipe's text, not its parsed form, salts the derivation, so a byte of whitespace
    /// or a reordered key yields a different secret.
    static func secret(seed: String, type: DerivableType, recipe: Recipe) -> [UInt8] {
        let info = Array(type.rawValue.utf8) + Array(recipe.json.utf8)
        return recipe.hashFunction.derive(seed: Array(seed.utf8), info: info, outputLength: recipe.lengthInBytes)
    }

    /// As crypto_box_seed_keypair does: the first 32 bytes of SHA-512 of the seed, unclamped.
    /// The curve multiplication clamps.
    static func x25519(secret: [UInt8]) -> (scalar: [UInt8], publicKey: [UInt8]) {
        let scalar = Array(SHA512.hash(data: secret).prefix(32))
        do {
            let key = try Curve25519.KeyAgreement.PrivateKey(rawRepresentation: scalar)
            return (scalar, Array(key.publicKey.rawRepresentation))
        } catch {
            preconditionFailure("X25519 rejected a 32-byte scalar: \(error)")
        }
    }

    /// The secret key is the seed followed by the public key, as libsodium lays it out.
    static func ed25519(seed: [UInt8]) -> [UInt8] {
        do {
            let key = try Curve25519.Signing.PrivateKey(rawRepresentation: seed)
            return seed + Array(key.publicKey.rawRepresentation)
        } catch {
            preconditionFailure("Ed25519 rejected a 32-byte seed: \(error)")
        }
    }
}
