//
//  GoldenVectorTests.swift
//  SeededCryptoTests
//
//  Every value in Fixtures/golden-vectors.json was produced by the reference C++
//  implementation (scripts/generate-golden-vectors.sh). If any of these tests fail,
//  derived passwords and keys have changed for real users. Do not "fix" the fixture;
//  fix the build.
//

import Foundation
import Testing
@testable import SeededCrypto

struct GoldenVector: Decodable, Sendable, CustomTestStringConvertible {
    var testDescription: String { name }

    let name: String
    let type: String
    let seed: String
    let recipe: String
    let recipeWithAllOptionalParametersSpecified: String
    let json: String
    let password: String?
    let secretBytesHex: String?
    let keyBytesHex: String?
    let signatureVerificationKeyJson: String?
    let openSshPublicKey: String?
    let openSshPemPrivateKey: String?
    let openPgpPemFormatSecretKey: String?
    let message: String?
    let signatureHex: String?
    let packagedSealedMessageJson: String?
    let sealingKeyJson: String?
}

struct GoldenFixture: Decodable, Sendable {
    let exampleDiceKeySeed: String
    let exampleDiceKeySeedWithoutOrientations: String
    let sodiumVersion: String
    let vectors: [GoldenVector]
}

let fixture: GoldenFixture = {
    let url = Bundle.module.url(forResource: "golden-vectors", withExtension: "json", subdirectory: "Fixtures")!
    // swiftlint:disable:next force_try
    return try! JSONDecoder().decode(GoldenFixture.self, from: Data(contentsOf: url))
}()

@Suite("Golden derivation vectors from the reference C++")
struct GoldenVectorTests {
    @Test("libsodium version matches the vendored source")
    func sodiumVersion() {
        #expect(Recipe.sodiumVersion == fixture.sodiumVersion)
    }

    @Test("recipes canonicalize identically", arguments: fixture.vectors)
    func recipeCanonicalization(vector: GoldenVector) throws {
        #expect(try Recipe.withAllOptionalParametersSpecified(vector.recipe) == vector.recipeWithAllOptionalParametersSpecified)
    }

    @Test("passwords", arguments: fixture.vectors.filter { $0.type == "Password" })
    func passwords(vector: GoldenVector) throws {
        let password = try Password.deriveFromSeed(withSeedString: vector.seed, recipe: vector.recipe)
        #expect(password.password == vector.password)
        #expect(password.toJson() == vector.json)
        #expect(try Password.from(json: vector.json).password == vector.password)
    }

    @Test("secrets", arguments: fixture.vectors.filter { $0.type == "Secret" })
    func secrets(vector: GoldenVector) throws {
        let secret = try Secret.deriveFromSeed(withSeedString: vector.seed, recipe: vector.recipe)
        #expect(secret.secretBytes().hexString == vector.secretBytesHex)
        #expect(secret.toJson() == vector.json)
        #expect(try Secret.from(json: vector.json).secretBytes() == secret.secretBytes())
    }

    @Test("signing keys, signatures and key encodings", arguments: fixture.vectors.filter { $0.type == "SigningKey" })
    func signingKeys(vector: GoldenVector) throws {
        let key = try SigningKey.deriveFromSeed(withSeedString: vector.seed, recipe: vector.recipe)
        #expect(key.toJson() == vector.json)
        #expect(key.signatureVerificationKey.toJson() == vector.signatureVerificationKeyJson)
        #expect(key.openSshPublicKey == vector.openSshPublicKey)
        // The OpenSSH private-key block embeds a random check value, so only its shape is stable.
        #expect(key.openSshPemPrivateKey.hasPrefix("-----BEGIN OPENSSH PRIVATE KEY-----"))
        #expect(key.openSshPemPrivateKey.count == vector.openSshPemPrivateKey?.count)
        #expect(key.openPgpPemFormatSecretKey == vector.openPgpPemFormatSecretKey)
        let message = try #require(vector.message)
        let signature = try key.generateSignature(withMessage: message)
        #expect(signature.hexString == vector.signatureHex)
        #expect(try key.signatureVerificationKey.verify(withMessage: message, signature: signature))
        #expect(try !key.signatureVerificationKey.verify(withMessage: message + "!", signature: signature))
    }

    @Test("symmetric keys unseal what the reference sealed", arguments: fixture.vectors.filter { $0.type == "SymmetricKey" })
    func symmetricKeys(vector: GoldenVector) throws {
        let key = try SymmetricKey.deriveFromSeed(withSeedString: vector.seed, recipe: vector.recipe)
        #expect(key.keyBytes.hexString == vector.keyBytesHex)
        #expect(key.toJson() == vector.json)
        let packaged = try #require(vector.packagedSealedMessageJson)
        let message = try #require(vector.message)
        #expect(String(decoding: try key.unseal(withJsonPackagedSealedMessage: packaged), as: UTF8.self) == message)
        #expect(String(decoding: try SymmetricKey.unseal(withJsonPackagedSealedMessage: packaged, seedString: vector.seed), as: UTF8.self) == message)
        let resealed = try key.seal(withMessage: message)
        #expect(String(decoding: try key.unseal(withPackagedSealedMessage: resealed), as: UTF8.self) == message)
    }

    @Test("unsealing keys unseal what the reference sealed", arguments: fixture.vectors.filter { $0.type == "UnsealingKey" })
    func unsealingKeys(vector: GoldenVector) throws {
        let key = try UnsealingKey.deriveFromSeed(withSeedString: vector.seed, recipe: vector.recipe)
        #expect(key.toJson() == vector.json)
        #expect(key.sealingKey().toJson() == vector.sealingKeyJson)
        let packaged = try #require(vector.packagedSealedMessageJson)
        let message = try #require(vector.message)
        #expect(String(decoding: try key.unseal(withJsonPackagedSealedMessage: packaged), as: UTF8.self) == message)
        #expect(String(decoding: try UnsealingKey.unseal(withJsonPackagedSealedMessage: packaged, seedString: vector.seed), as: UTF8.self) == message)
        let resealed = try key.sealingKey().seal(withMessage: message)
        #expect(String(decoding: try key.unseal(withPackagedSealedMessage: resealed), as: UTF8.self) == message)
    }

    @Test("invalid recipe JSON throws instead of crashing")
    func invalidRecipe() {
        #expect(throws: SeededCryptoError.self) {
            try Password.deriveFromSeed(withSeedString: "seed", recipe: "{not json")
        }
    }
}
