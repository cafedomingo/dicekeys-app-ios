//
//  DiceKeySeedTests.swift
//  DiceKeyVaultTests
//
//  The seeds come from kinds.json, where scripts/derive-kinds.py checks them against the
//  original DiceKeys C++. If they fail, DiceKey canonicalization changed and every derived
//  secret with it.
//

import Derivation
import Foundation
import Testing

@testable import DiceKeyVault

@Suite("DiceKey seed canonicalization")
struct DiceKeySeedTests {
    static let exampleSeed = "A1tB2rC3bD4lE5tF6rG1bH2lI3tJ4rK5bL6lM1tN2rO3bP4lR5tS6rT1bU2lV3tW4rX5bY6lZ1t"

    struct SeedVector: Decodable, Sendable {
        let text: String
        let seed: String
    }

    /// The DiceKeys in kinds.json, some written in a non-canonical rotation, with the seeds
    /// scripts/derive-kinds.py checks against the original DiceKeys C++.
    static let seedVectors: [SeedVector] = {
        struct Fixture: Decodable { let seeds: [SeedVector] }
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent()
        let url = root.appending(path: "Packages/Derivation/Tests/DerivationTests/Fixtures/kinds.json")
        // swiftlint:disable:next force_try
        return try! JSONDecoder().decode(Fixture.self, from: Data(contentsOf: url)).seeds
    }()

    @Test("the fixture's DiceKeys produce the fixture's seeds", arguments: seedVectors)
    func fixtureSeeds(vector: SeedVector) throws {
        #expect(try DiceKey(text: vector.text).seed == vector.seed)
    }

    @Test("DiceKey.example produces the original DiceKeys seed")
    func exampleSeed() {
        #expect(DiceKey.example.seed == Self.exampleSeed)
    }

    @Test("every rotation of a DiceKey produces the same seed")
    func rotationInvariance() {
        let key = DiceKey.example
        var rotated = key
        for _ in 0..<3 {
            rotated = rotated.turnedClockwise()
            #expect(rotated.seed == key.seed)
        }
    }

    @Test("the DiceKey id is DiceKeyID's, which kinds.json pins")
    func diceKeyId() {
        #expect(DiceKey.example.id == DiceKeyID.derive(seed: DiceKey.example.seed))
    }

    @Test("text round-trips")
    func textRoundTrip() throws {
        let key = DiceKey.example
        let restored = try DiceKey(text: key.text)
        #expect(restored == key)
    }

    @Test(
        "text of the wrong length throws instead of trapping",
        arguments: ["", "A1t", String(repeating: "A1t", count: 24)])
    func wrongLengthThrows(text: String) {
        #expect(throws: DiceKeyFormatError.self) {
            try DiceKey(text: text)
        }
    }

    @Test("the id is the same on every read and every turn")
    func idIsStable() {
        let key = DiceKey.example.turnedClockwise()
        #expect(key.id == key.id)
        #expect(key.id == DiceKey.example.id)
    }
}
