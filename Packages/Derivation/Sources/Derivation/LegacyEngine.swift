//
//  LegacyEngine.swift
//  Derivation
//

import SeededCrypto

/// The reference C++ (seeded-crypto over libsodium), reached through the SeededCrypto
/// package. Its own recipe parsing runs again inside, so anything the strict `Recipe`
/// accepted and the C++ still refuses surfaces as `engineRejected`.
struct LegacyEngine: DerivationEngine {
    func derive(_ type: DerivableType, seed: String, recipe: String) throws(DerivationError) -> String {
        do {
            switch type {
            case .password:
                return try SeededCrypto.Password.deriveFromSeed(withSeedString: seed, recipe: recipe).toJson()
            case .secret:
                return try SeededCrypto.Secret.deriveFromSeed(withSeedString: seed, recipe: recipe).toJson()
            case .symmetricKey:
                return try SeededCrypto.SymmetricKey.deriveFromSeed(withSeedString: seed, recipe: recipe).toJson()
            case .unsealingKey:
                return try SeededCrypto.UnsealingKey.deriveFromSeed(withSeedString: seed, recipe: recipe).toJson()
            case .signingKey:
                return try SeededCrypto.SigningKey.deriveFromSeed(withSeedString: seed, recipe: recipe).toJson()
            }
        } catch let error as SeededCryptoError {
            throw .engineRejected(error.message)
        } catch {
            throw .internalError(String(describing: error))
        }
    }
}
