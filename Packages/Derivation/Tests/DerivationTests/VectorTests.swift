//
//  VectorTests.swift
//  DerivationTests
//
//  Every value in Fixtures/vectors.json was produced by the reference C++ implementation
//  before it was replaced. If a `cases` or `legacy` test fails, derived passwords
//  and keys have changed for real users. Do not "fix" the fixture; fix the build.
//

import Foundation
import Testing
@testable import Derivation

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

    var derivableType: DerivableType? { DerivableType(rawValue: type) }
}

struct FixtureDiceKey: Decodable, Sendable {
    let name: String
    let humanReadableForm: String
    let seed: String
    let seedWithoutOrientations: String
}

struct VectorFixture: Decodable, Sendable {
    let diceKeys: [FixtureDiceKey]
    let cases: [Vector]
    let legacy: [Vector]
    let rejected: [Vector]
}

let fixture: VectorFixture = {
    let url = Bundle.module.url(forResource: "vectors", withExtension: "json", subdirectory: "Fixtures")!
    // swiftlint:disable:next force_try
    return try! JSONDecoder().decode(VectorFixture.self, from: Data(contentsOf: url))
}()

extension Data {
    var hex: String { map { String(format: "%02x", $0) }.joined() }
}

@Suite("Derivation vectors from the reference C++")
struct VectorTests {
    @Test("the fixture holds the expected sections")
    func sections() {
        #expect(fixture.diceKeys.count == 4)
        #expect(fixture.cases.count == 168)
        #expect(fixture.legacy.count == 21)
        #expect(fixture.rejected.count == 16)
        #expect(fixture.legacy.allSatisfy { $0.note != nil })
    }

    @Test("every case derives to the recorded value through the public API", arguments: fixture.cases)
    func derives(vector: Vector) throws {
        let json = try #require(vector.json)
        switch try #require(vector.derivableType) {
        case .password:
            let password = try Password.derive(seed: vector.seed, recipe: vector.recipe)
            #expect(password.password == vector.password)
            #expect(password.toJson() == json)
            #expect(password.recipe.json == vector.recipe)
        case .secret:
            let secret = try Secret.derive(seed: vector.seed, recipe: vector.recipe)
            #expect(secret.bytes.hex == vector.secretBytesHex)
            #expect(secret.toJson() == json)
        case .symmetricKey:
            let key = try SymmetricKey.derive(seed: vector.seed, recipe: vector.recipe)
            #expect(key.keyBytes.hex == vector.keyBytesHex)
            #expect(key.toJson() == json)
        case .unsealingKey:
            let key = try UnsealingKey.derive(seed: vector.seed, recipe: vector.recipe)
            #expect(key.unsealingKeyBytes.hex == vector.unsealingKeyBytesHex)
            #expect(key.sealingKeyBytes.hex == vector.sealingKeyBytesHex)
            #expect(key.toJson() == json)
        case .signingKey:
            let key = try SigningKey.derive(seed: vector.seed, recipe: vector.recipe)
            #expect(key.signingKeyBytes.hex == vector.signingKeyBytesHex)
            #expect(key.toJson() == json)
        }
    }

    // The strict parser refuses every legacy recipe; the fixture records what the C++
    // produced for them so the behavior could be restored.
    @Test("every legacy entry is refused by the parser", arguments: fixture.legacy)
    func legacy(vector: Vector) throws {
        let type = try #require(vector.derivableType)
        #expect(throws: DerivationError.self) { try Recipe(json: vector.recipe, type: type) }
    }

    // The C++ refused one recipe that is correct, so that entry derives here and every
    // other entry is refused by the parser.
    @Test("every rejected entry is refused, except the one the port derives", arguments: fixture.rejected)
    func rejects(vector: Vector) throws {
        let type = try #require(vector.derivableType)
        if vector.name == "consistent lengthInBits and lengthInWords" {
            #expect(try Recipe(json: vector.recipe, type: type).lengthInWords == 10)
            #expect(try Password.derive(seed: vector.seed, recipe: vector.recipe).password.hasPrefix("10-"))
        } else {
            #expect(throws: DerivationError.self) { try Recipe(json: vector.recipe, type: type) }
        }
    }

    @Test("a consistent lengthInBits and lengthInWords pair derives")
    func consistentBitsAndWords() throws {
        // The C++ rejected this correct pair; the port derives it.
        let json = #"{"lengthInBits":90,"lengthInWords":10}"#
        let password = try Password.derive(seed: fixture.diceKeys[0].seed, recipe: json)
        #expect(password.password.hasPrefix("10-"))
    }

    @Test("the same recipe on the two orientation forms of one key derives different values")
    func orientationsMatter() throws {
        let key = fixture.diceKeys[0]
        let with = try Secret.derive(seed: key.seed, recipe: "")
        let without = try Secret.derive(seed: key.seedWithoutOrientations, recipe: "")
        #expect(with.bytes != without.bytes)
    }
}
