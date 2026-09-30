//
//  HKDFTests.swift
//  DerivationTests
//

import Foundation
import Testing
import SeededCrypto
@testable import Derivation

@Suite("HKDF over BLAKE2b against the C++")
struct HKDFTests {
    /// The C++ hashes the type string followed by the recipe; a recipe that names its type
    /// makes the shim's untyped entry point use that string, so both sides hash the same info.
    private func compare(seed: String, recipe: String, length: Int) throws {
        let typed = ##"{"type":"Secret","lengthInBytes":\##(length)"## + (recipe.isEmpty ? "}" : "," + String(recipe.dropFirst()))
        let expected = try SeededCrypto.Recipe.derivePrimarySecret(seedString: seed, recipe: typed)
        let info = Array("Secret".utf8) + Array(typed.utf8)
        #expect(Data(HKDFBlake2b.derive(seed: Array(seed.utf8), info: info, outputLength: length)) == expected, "\(typed)")
        #expect(Data(Derivation.HashFunction.blake2b.derive(seed: Array(seed.utf8), info: info, outputLength: length)) == expected)
    }

    @Test("lengths at the block boundaries", arguments: [1, 31, 32, 33, 63, 64, 65, 255, 256, 1000, 8159, 8160])
    func boundaries(length: Int) throws {
        try compare(seed: fixture.diceKeys[0].seed, recipe: #"{"purpose":"hkdf"}"#, length: length)
    }

    @Test("every fixture DiceKey, with and without orientations")
    func fixtureSeeds() throws {
        for key in fixture.diceKeys {
            try compare(seed: key.seed, recipe: "", length: 32)
            try compare(seed: key.seedWithoutOrientations, recipe: "", length: 32)
        }
    }

    @Test("random seeds, recipes and lengths")
    func random() throws {
        var generator = SplitMix64(seed: 5)
        for _ in 0..<300 {
            let seedLength = Int.random(in: 0...200, using: &generator)
            let seed = String((0..<seedLength).map { _ in "ABCDEFGHJKLMNPRSTUVWXYZ123456trbl".randomElement(using: &generator)! })
            let purpose = String((0..<Int.random(in: 0...40, using: &generator)).map { _ in "abcdefghijklmnopqrstuvwxyz ".randomElement(using: &generator)! })
            let length = Int.random(in: 1...8160, using: &generator)
            try compare(seed: seed, recipe: #"{"purpose":"\#(purpose)"}"#, length: length)
        }
    }

    @Test("the empty seed and the one-byte seed derive")
    func shortSeeds() throws {
        try compare(seed: "", recipe: "", length: 32)
        try compare(seed: "A", recipe: "", length: 32)
    }
}

/// A small deterministic generator so a failing random case can be reproduced from its seed.
struct SplitMix64: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9e37_79b9_7f4a_7c15
        var z = state
        z = (z ^ (z >> 30)) &* 0xbf58_476d_1ce4_e5b9
        z = (z ^ (z >> 27)) &* 0x94d0_49bb_1331_11eb
        return z ^ (z >> 31)
    }
}
