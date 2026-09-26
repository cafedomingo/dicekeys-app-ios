//
//  DiceKeySeedTests.swift
//  DiceKeysTests
//
//  The seed string is the only input to every derivation. These expectations were
//  computed independently of the app (see scripts/generate-golden-vectors.cpp and the
//  fixture in Packages/DiceKeysCore/Tests/SeededCryptoTests/Fixtures). If they fail,
//  DiceKey canonicalization changed and every derived secret changes with it.
//

import Foundation
import Testing
import SeededCrypto
@testable import DiceKeys

@Suite("DiceKey seed canonicalization")
struct DiceKeySeedTests {
    static let exampleSeed = "A1tB2rC3bD4lE5tF6rG1bH2lI3tJ4rK5bL6lM1tN2rO3bP4lR5tS6rT1bU2lV3tW4rX5bY6lZ1t"
    static let exampleSeedWithoutOrientations = "A1B2C3D4E5F6G1H2I3J4K5L6M1N2O3P4R5S6T1U2V3W4X5Y6Z1"

    @Test("DiceKey.Example produces the golden seed")
    func exampleSeed() {
        #expect(DiceKey.Example.toSeed() == Self.exampleSeed)
        #expect(DiceKey.Example.toSeed(includeOrientations: false) == Self.exampleSeedWithoutOrientations)
    }

    @Test("every rotation of a DiceKey produces the same seed")
    func rotationInvariance() {
        let key = DiceKey.Example
        var rotated = key
        for _ in 0..<3 {
            rotated = rotated.rotatedClockwise90Degrees()
            #expect(rotated.toSeed() == key.toSeed())
        }
    }

    @Test("the 16-byte DiceKey id matches the reference derivation")
    func diceKeyId() {
        // Derived by the reference C++ for the example seed with
        // {"purpose":"a unique identifier for this DiceKey","lengthInBytes":16}.
        #expect(DiceKey.Example.idBytes.map { String(format: "%02x", $0) }.joined() == "31f6979a628e4800780118a5dc466129")
    }

    @Test("human-readable form round-trips")
    func humanReadableRoundTrip() throws {
        let key = DiceKey.Example
        let restored = try DiceKey.createFrom(humanReadableForm: key.toHumanReadableForm())
        #expect(restored == key)
    }

    @Test("a human-readable form of the wrong length throws instead of trapping",
          arguments: ["", "A1t", String(repeating: "A1t", count: 24)])
    func wrongLengthThrows(humanReadableForm: String) {
        #expect(throws: IllegalCharacterError.self) {
            try DiceKey.createFrom(humanReadableForm: humanReadableForm)
        }
    }

    @Test("the id is the same on every read")
    func idIsStable() {
        let key = DiceKey.createFromRandom()
        #expect(key.id == key.id)
        #expect(key.id == DiceKey(key.faces).id)
    }
}
