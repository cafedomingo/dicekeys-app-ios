//
//  Engine.swift
//  Derivation
//

import CryptoKit
import Foundation

/// HKDF-SHA256 for the bytes, CryptoKit for the curves.
enum Engine {
    static let keyLength = 32

    /// RFC 5869 HKDF with SHA-256 and no salt. `info` is the type's name followed by the
    /// recipe's text: the text itself, not what it means, so a changed byte is a different key.
    static func bytes(seed: String, type: DerivableType, recipe: String, length: Int) -> [UInt8] {
        let key = HKDF<SHA256>.deriveKey(
            inputKeyMaterial: SymmetricKey(data: Data(seed.utf8)), info: Data((type.rawValue + recipe).utf8),
            outputByteCount: length)
        return key.withUnsafeBytes { Array($0) }
    }

    /// The public key of a scalar, which the curve multiplication clamps.
    static func x25519PublicKey(scalar: [UInt8]) -> [UInt8] {
        do {
            return Array(try Curve25519.KeyAgreement.PrivateKey(rawRepresentation: scalar).publicKey.rawRepresentation)
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
