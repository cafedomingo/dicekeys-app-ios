//
//  VectorTests.swift
//  SeededCryptoTests
//
//  Every value in Fixtures/vectors.json was produced by the reference C++ implementation
//  (scripts/generate-vectors.sh). If a `cases` or `legacy` test fails, derived passwords
//  and keys have changed for real users. Do not "fix" the fixture; fix the build.
//

import Foundation
import Testing
@testable import SeededCrypto

struct Vector: Decodable, Sendable, CustomTestStringConvertible {
    var testDescription: String { name }

    let name: String
    let seed: String
    let type: String
    let recipe: String
    let note: String?
    let json: String?
    let error: String?
    let password: String?
    let secretBytesHex: String?
    let keyBytesHex: String?
    let sealingKeyBytesHex: String?
    let unsealingKeyBytesHex: String?
    let signingKeyBytesHex: String?
    let openSshPublicKey: String?
    let sshComment: String?
    let openSshPemPrivateKey: String?
    let pgpUserId: String?
    let pgpTimestamp: UInt32?
    let openPgpPemFormatSecretKey: String?
}

struct FixtureDiceKey: Decodable, Sendable {
    let name: String
    let humanReadableForm: String
    let seed: String
    let seedWithoutOrientations: String
}

struct VectorFixture: Decodable, Sendable {
    let sodiumVersion: String
    let diceKeys: [FixtureDiceKey]
    let cases: [Vector]
    let legacy: [Vector]
    let rejected: [Vector]

    var exampleDiceKeySeed: String { diceKeys[0].seed }
}

let fixture: VectorFixture = {
    let url = Bundle.module.url(forResource: "vectors", withExtension: "json", subdirectory: "Fixtures")!
    // swiftlint:disable:next force_try
    return try! JSONDecoder().decode(VectorFixture.self, from: Data(contentsOf: url))
}()

@Suite("Derivation vectors from the reference C++")
struct VectorTests {
    @Test("libsodium version matches the vendored source")
    func sodiumVersion() {
        #expect(Recipe.sodiumVersion == fixture.sodiumVersion)
    }

    @Test("the fixture holds the expected sections")
    func sections() {
        #expect(fixture.diceKeys.count == 4)
        #expect(fixture.cases.count > 150)
        #expect(!fixture.legacy.isEmpty)
        #expect(!fixture.rejected.isEmpty)
        #expect(fixture.legacy.allSatisfy { $0.note != nil })
    }

    // `legacy` entries derive on the C++ exactly like `cases`; they are separated only because
    // the Swift port will treat them differently.
    @Test("every case and legacy entry derives to the recorded value", arguments: fixture.cases + fixture.legacy)
    func derives(vector: Vector) throws {
        let json = try #require(vector.json)
        switch vector.type {
        case "Password":
            let password = try Password.deriveFromSeed(withSeedString: vector.seed, recipe: vector.recipe)
            #expect(password.password == vector.password)
            #expect(password.toJson() == json)
        case "Secret":
            let secret = try Secret.deriveFromSeed(withSeedString: vector.seed, recipe: vector.recipe)
            #expect(secret.secretBytes().hexString == vector.secretBytesHex)
            #expect(secret.toJson() == json)
        case "SymmetricKey":
            let key = try SymmetricKey.deriveFromSeed(withSeedString: vector.seed, recipe: vector.recipe)
            #expect(key.keyBytes.hexString == vector.keyBytesHex)
            #expect(key.toJson() == json)
        case "UnsealingKey":
            let key = try UnsealingKey.deriveFromSeed(withSeedString: vector.seed, recipe: vector.recipe)
            #expect(key.unsealingKeyBytes.hexString == vector.unsealingKeyBytesHex)
            #expect(key.sealingKeyBytes.hexString == vector.sealingKeyBytesHex)
            #expect(key.toJson() == json)
        case "SigningKey":
            let key = try SigningKey.deriveFromSeed(withSeedString: vector.seed, recipe: vector.recipe)
            #expect(key.signingKeyBytes.hexString == vector.signingKeyBytesHex)
            #expect(key.toJson() == json)
            #expect(key.openSshPublicKey == vector.openSshPublicKey)
            let sshPrivate = try key.openSshPemPrivateKey(comment: vector.sshComment ?? "")
            // The OpenSSH private key block embeds a random check value, so only its shape is stable.
            #expect(sshPrivate.hasPrefix("-----BEGIN OPENSSH PRIVATE KEY-----"))
            #expect(sshPrivate.count == vector.openSshPemPrivateKey?.count)
            let pgp = try key.openPgpPemFormatSecretKey(userId: vector.pgpUserId ?? "", timestamp: vector.pgpTimestamp ?? 0)
            #expect(pgp == vector.openPgpPemFormatSecretKey)
        default:
            Issue.record("unknown type \(vector.type)")
        }
    }

    @Test("every rejected entry throws", arguments: fixture.rejected)
    func rejects(vector: Vector) {
        #expect(vector.error?.isEmpty == false)
        #expect(throws: SeededCryptoError.self) {
            switch vector.type {
            case "Password": _ = try Password.deriveFromSeed(withSeedString: vector.seed, recipe: vector.recipe)
            case "Secret": _ = try Secret.deriveFromSeed(withSeedString: vector.seed, recipe: vector.recipe)
            case "SymmetricKey": _ = try SymmetricKey.deriveFromSeed(withSeedString: vector.seed, recipe: vector.recipe)
            case "UnsealingKey": _ = try UnsealingKey.deriveFromSeed(withSeedString: vector.seed, recipe: vector.recipe)
            default: _ = try SigningKey.deriveFromSeed(withSeedString: vector.seed, recipe: vector.recipe)
            }
        }
    }

    @Test("the same recipe on the two orientation forms of one key derives different values")
    func orientationsMatter() throws {
        let key = fixture.diceKeys[0]
        let with = try Secret.deriveFromSeed(withSeedString: key.seed, recipe: "")
        let without = try Secret.deriveFromSeed(withSeedString: key.seedWithoutOrientations, recipe: "")
        #expect(with.secretBytes() != without.secretBytes())
    }
}
