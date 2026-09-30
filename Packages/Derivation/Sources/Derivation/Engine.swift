//
//  Engine.swift
//  Derivation
//

import CryptoKit
import Foundation

/// The derivation: HKDF over BLAKE2b for the bytes, CryptoKit for the curves, and the
/// reference JSON layout for the result. Every `derive` on the derived types comes here.
struct Engine: Sendable {
    func derive(_ type: DerivableType, seed: String, recipe: String) throws(DerivationError) -> String {
        let parsed = try Recipe(json: recipe, type: type)
        let info = Array(type.rawValue.utf8) + Array(recipe.utf8)
        let secret = parsed.hashFunction.derive(seed: Array(seed.utf8), info: info, outputLength: parsed.lengthInBytes)
        // The C++ omits an empty recipe for these three types and writes it for the key pairs.
        let optionalRecipe: [(key: String, value: String)] = recipe.isEmpty ? [] : [(key: "recipe", value: recipe)]
        switch type {
        case .password:
            let password = PasswordFormatter.password(from: secret, wordList: parsed.wordList, lengthInChars: parsed.lengthInChars)
            return ReferenceJSON.object([(key: "password", value: password)] + optionalRecipe)
        case .secret:
            return ReferenceJSON.object([(key: "secretBytes", value: ReferenceJSON.hex(secret))] + optionalRecipe)
        case .symmetricKey:
            return ReferenceJSON.object([(key: "keyBytes", value: ReferenceJSON.hex(secret))] + optionalRecipe)
        case .unsealingKey:
            // libsodium's crypto_box_seed_keypair hashes the seed with SHA-512 and keeps the
            // first 32 bytes as the scalar, unclamped; the curve multiplication clamps.
            let scalar = Array(SHA512.hash(data: secret).prefix(32))
            let publicKey: [UInt8]
            do {
                publicKey = Array(try Curve25519.KeyAgreement.PrivateKey(rawRepresentation: scalar).publicKey.rawRepresentation)
            } catch {
                throw .internalError("X25519 rejected a 32-byte scalar: \(error)")
            }
            return ReferenceJSON.object([
                (key: "recipe", value: recipe),
                (key: "sealingKeyBytes", value: ReferenceJSON.hex(publicKey)),
                (key: "unsealingKeyBytes", value: ReferenceJSON.hex(scalar))
            ])
        case .signingKey:
            let publicKey: [UInt8]
            do {
                publicKey = Array(try Curve25519.Signing.PrivateKey(rawRepresentation: secret).publicKey.rawRepresentation)
            } catch {
                throw .internalError("Ed25519 rejected a 32-byte seed: \(error)")
            }
            // libsodium's secret key is the seed followed by the public key.
            return ReferenceJSON.object([
                (key: "recipe", value: recipe),
                (key: "signingKeyBytes", value: ReferenceJSON.hex(secret + publicKey))
            ])
        }
    }
}
