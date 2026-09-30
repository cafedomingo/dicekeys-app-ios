//
//  LibsodiumCrossCheckTests.swift
//  BLAKE2Tests
//
//  libsodium's BLAKE2b is the implementation every DiceKeys derivation has used so far.
//  While it is still in the tree, the Swift primitive is compared against it over random
//  messages, keys and digest lengths. Gone with the C++.
//

import CSodium
import Testing
import BLAKE2

private func libsodiumHash(_ message: [UInt8], key: [UInt8], digestLength: Int) -> [UInt8] {
    var out = [UInt8](repeating: 0, count: digestLength)
    let result = message.withUnsafeBufferPointer { messagePointer in
        key.withUnsafeBufferPointer { keyPointer in
            crypto_generichash_blake2b(&out, digestLength, messagePointer.baseAddress, UInt64(message.count), keyPointer.baseAddress, key.count)
        }
    }
    #expect(result == 0)
    return out
}

@Suite("BLAKE2b against libsodium", .serialized)
struct LibsodiumCrossCheckTests {
    init() {
        // Idempotent; libsodium's own tests call it the same way.
        _ = sodium_init()
    }

    @Test("every digest length and every key length", arguments: 1...64)
    func digestAndKeyLengths(digestLength: Int) {
        let message = Array("The quick brown fox jumps over the lazy dog".utf8)
        for keyLength in 0...64 {
            let key = (0..<keyLength).map { UInt8($0) }
            #expect(BLAKE2b.hash(message, key: key, digestLength: digestLength) == libsodiumHash(message, key: key, digestLength: digestLength), "digest \(digestLength), key \(keyLength)")
        }
    }

    @Test("10,000 random messages, keys and digest lengths")
    func randomInputs() {
        var generator = SplitMix64(seed: 20260929)
        for iteration in 0..<10_000 {
            let messageLength = Int.random(in: 0...1024, using: &generator)
            let keyLength = Int.random(in: 0...64, using: &generator)
            let digestLength = Int.random(in: 1...64, using: &generator)
            let message = (0..<messageLength).map { _ in UInt8.random(in: .min ... .max, using: &generator) }
            let key = (0..<keyLength).map { _ in UInt8.random(in: .min ... .max, using: &generator) }
            let ours = BLAKE2b.hash(message, key: key, digestLength: digestLength)
            let theirs = libsodiumHash(message, key: key, digestLength: digestLength)
            if ours != theirs {
                Issue.record("iteration \(iteration): message \(messageLength) bytes, key \(keyLength) bytes, digest \(digestLength)")
                return
            }
        }
    }

    @Test("streaming matches libsodium's streaming at random split points")
    func randomStreaming() {
        var generator = SplitMix64(seed: 7)
        // The C state is over-aligned (64 bytes), so Swift does not import the struct and the
        // functions take an OpaquePointer to memory the test allocates itself.
        let stateMemory = UnsafeMutableRawPointer.allocate(byteCount: MemoryLayout<UInt8>.stride * 384, alignment: 64)
        defer { stateMemory.deallocate() }
        let state = OpaquePointer(stateMemory)
        for iteration in 0..<500 {
            let message = (0..<Int.random(in: 0...2048, using: &generator)).map { _ in UInt8.random(in: .min ... .max, using: &generator) }
            let key = (0..<Int.random(in: 0...64, using: &generator)).map { _ in UInt8.random(in: .min ... .max, using: &generator) }
            let digestLength = Int.random(in: 1...64, using: &generator)
            let splitCount = Int.random(in: 0...5, using: &generator)
            let splits = (0..<splitCount).map { _ in Int.random(in: 0...message.count, using: &generator) }.sorted()

            var ours = BLAKE2b(digestLength: digestLength, key: key)
            let initResult = key.withUnsafeBufferPointer { crypto_generichash_blake2b_init(state, $0.baseAddress, key.count, digestLength) }
            #expect(initResult == 0)
            var start = 0
            for end in splits + [message.count] {
                let chunk = Array(message[start..<end])
                ours.update(chunk)
                _ = chunk.withUnsafeBufferPointer { crypto_generichash_blake2b_update(state, $0.baseAddress, UInt64(chunk.count)) }
                start = end
            }
            var theirs = [UInt8](repeating: 0, count: digestLength)
            _ = crypto_generichash_blake2b_final(state, &theirs, digestLength)
            if ours.finalize() != theirs {
                Issue.record("iteration \(iteration): message \(message.count) bytes, key \(key.count) bytes, digest \(digestLength), splits \(splits)")
                return
            }
        }
    }
}
