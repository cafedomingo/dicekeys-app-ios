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

/// The binary body of an OpenSSH private key with its two check-int copies zeroed. The private
/// section starts after the magic, the cipher, KDF and KDF options strings, the key count, the
/// public key blob and the section length.
private func maskedOpenSshKey(_ pem: String) throws -> [UInt8] {
    let body = pem.split(separator: "\n").filter { !$0.hasPrefix("-----") }.joined()
    var bytes = [UInt8](try #require(Data(base64Encoded: body)))
    var offset = "openssh-key-v1\0".utf8.count
    func uint32(at index: Int) -> Int {
        bytes[index..<index + 4].reduce(0) { $0 << 8 | Int($1) }
    }
    for _ in 0..<3 { offset += 4 + uint32(at: offset) }
    offset += 4
    offset += 4 + uint32(at: offset)
    offset += 4
    for index in offset..<offset + 8 { bytes[index] = 0 }
    return bytes
}

@Suite("Derivation vectors from the reference C++")
struct VectorTests {
    @Test("libsodium version matches the vendored source")
    func sodiumVersion() {
        #expect(Recipe.sodiumVersion == fixture.sodiumVersion)
    }

    @Test("the fixture holds the expected sections")
    func sections() {
        #expect(fixture.diceKeys.count == 4)
        #expect(fixture.cases.count == 168)
        #expect(fixture.legacy.count == 21)
        #expect(fixture.rejected.count == 16)
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
            // The block embeds a random check value, so the Swift output is compared with it zeroed.
            let recorded = try #require(vector.openSshPemPrivateKey)
            #expect(sshPrivate.count == recorded.count)
            #expect(try maskedOpenSshKey(sshPrivate) == maskedOpenSshKey(recorded))
            let pgp = try key.openPgpPemFormatSecretKey(userId: vector.pgpUserId ?? "", timestamp: vector.pgpTimestamp ?? 0)
            #expect(pgp == vector.openPgpPemFormatSecretKey)
        default:
            Issue.record("unknown type \(vector.type)")
        }
    }

    @Test("every rejected entry throws", arguments: fixture.rejected)
    func rejects(vector: Vector) throws {
        #expect(throws: SeededCryptoError(message: try #require(vector.error))) {
            switch vector.type {
            case "Password": _ = try Password.deriveFromSeed(withSeedString: vector.seed, recipe: vector.recipe)
            case "Secret": _ = try Secret.deriveFromSeed(withSeedString: vector.seed, recipe: vector.recipe)
            case "SymmetricKey": _ = try SymmetricKey.deriveFromSeed(withSeedString: vector.seed, recipe: vector.recipe)
            case "UnsealingKey": _ = try UnsealingKey.deriveFromSeed(withSeedString: vector.seed, recipe: vector.recipe)
            case "SigningKey": _ = try SigningKey.deriveFromSeed(withSeedString: vector.seed, recipe: vector.recipe)
            default: Issue.record("unknown type \(vector.type)")
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
