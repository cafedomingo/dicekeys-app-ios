//
//  DiceKeySeedTests.swift
//  DiceKeysTests
//
//  The expectations come from Packages/Derivation/Tests/DerivationTests/Fixtures, recorded
//  independently of the app. If they fail, DiceKey canonicalization changed and every
//  derived secret with it.
//

import Foundation
import Testing

@testable import DiceKeys

@Suite("DiceKey seed canonicalization")
struct DiceKeySeedTests {
    static let exampleSeed = "A1tB2rC3bD4lE5tF6rG1bH2lI3tJ4rK5bL6lM1tN2rO3bP4lR5tS6rT1bU2lV3tW4rX5bY6lZ1t"

    /// The four DiceKeys in the derivation fixture, as (human-readable form, seed). The last
    /// two are written in a non-canonical rotation.
    static let fixtureDiceKeys: [(form: String, seed: String)] = [
        (
            "A1tB2rC3bD4lE5tF6rG1bH2lI3tJ4rK5bL6lM1tN2rO3bP4lR5tS6rT1bU2lV3tW4rX5bY6lZ1t",
            "A1tB2rC3bD4lE5tF6rG1bH2lI3tJ4rK5bL6lM1tN2rO3bP4lR5tS6rT1bU2lV3tW4rX5bY6lZ1t"
        ),
        (
            "F2lY4rC2bV6bX4rK1rD5lS4bG6bZ2lU4rA6tI5bB1lT3rP3lL6lH6lN2tE2rO2rW1tJ5lR1tM2b",
            "F2lY4rC2bV6bX4rK1rD5lS4bG6bZ2lU4rA6tI5bB1lT3rP3lL6lH6lN2tE2rO2rW1tJ5lR1tM2b"
        ),
        (
            "I5lW5tZ5tY2tD3rU1lX3bB4bA2bL2lC1lO1tP1tM2bS1lT1bR3lN2lJ3lE2rF3rG3rV5tH1lK3r",
            "D3tL2bS1bE2tK3tY2lA2rM2rJ3bH1bZ5lB4rP1lN2bV5lW5lX3rO1lR3bG3tI5bU1bC1bT1rF3t"
        ),
        (
            "N1rO6lX2tZ1lY5rA6rR1lE6bD2bM3bB4tP1tC6lU1tI3rK1tL6lW1rH1rJ2lF5lV4lT2rS4bG2l",
            "F5tK1rB4rA6bN1bV4tL6tP1rR1tO6tT2bW1bC6tE6lX2rS4lH1bU1rD2lZ1tG2tJ2tI3bM3lY5b"
        )
    ]

    @Test("the fixture's DiceKeys produce the fixture's seeds", arguments: fixtureDiceKeys)
    func fixtureSeeds(key: (form: String, seed: String)) throws {
        #expect(try DiceKey(humanReadableForm: key.form).seed == key.seed)
    }

    @Test("DiceKey.example produces the reference seed")
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

    @Test("the 16-byte DiceKey id matches the reference derivation")
    func diceKeyId() {
        // Derived by the reference C++ for the example seed with
        // {"purpose":"a unique identifier for this DiceKey","lengthInBytes":16}.
        #expect(
            DiceKey.example.idBytes.map { String(format: "%02x", $0) }.joined() == "31f6979a628e4800780118a5dc466129")
    }

    @Test("human-readable form round-trips")
    func humanReadableRoundTrip() throws {
        let key = DiceKey.example
        let restored = try DiceKey(humanReadableForm: key.humanReadableForm)
        #expect(restored == key)
    }

    @Test(
        "a human-readable form of the wrong length throws instead of trapping",
        arguments: ["", "A1t", String(repeating: "A1t", count: 24)])
    func wrongLengthThrows(humanReadableForm: String) {
        #expect(throws: DiceKeyFormatError.self) {
            try DiceKey(humanReadableForm: humanReadableForm)
        }
    }

    @Test("the id is the same on every read and every turn")
    func idIsStable() {
        let key = DiceKey.example.turnedClockwise()
        #expect(key.id == key.id)
        #expect(key.id == DiceKey.example.id)
    }
}
