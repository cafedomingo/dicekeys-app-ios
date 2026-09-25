//
//  ConcurrentFirstUseTests.swift
//  SeededCryptoTests
//
//  Regression test for libsodium being built without HAVE_PTHREAD: sodium_init() then
//  has no lock, concurrent first calls each re-randomise the guarded-memory canary, and
//  the first sodium_free() aborts the process (SIGABRT in _out_of_bounds). It reproduced
//  in roughly one of three fresh processes running the golden vectors in parallel.
//

import Foundation
import Testing
@testable import SeededCrypto

@Suite("Concurrent use")
struct ConcurrentFirstUseTests {
    @Test("many threads may derive at once, including the very first derivation")
    func concurrentDerivations() async throws {
        let seed = fixture.exampleDiceKeySeed
        let expected = try Secret.deriveFromSeed(withSeedString: seed, recipe: #"{"purpose":"concurrency"}"#).secretBytes()
        try await withThrowingTaskGroup(of: Data.self) { group in
            for i in 0..<64 {
                group.addTask {
                    // Distinct recipes so every task allocates and frees its own guarded buffers.
                    let recipe = #"{"purpose":"concurrency","lengthInBytes":\#(32 + i % 8)}"#
                    let bytes = try Secret.deriveFromSeed(withSeedString: seed, recipe: recipe).secretBytes()
                    #expect(bytes.count == 32 + i % 8)
                    return try Secret.deriveFromSeed(withSeedString: seed, recipe: #"{"purpose":"concurrency"}"#).secretBytes()
                }
            }
            for try await bytes in group {
                #expect(bytes == expected)
            }
        }
    }
}
