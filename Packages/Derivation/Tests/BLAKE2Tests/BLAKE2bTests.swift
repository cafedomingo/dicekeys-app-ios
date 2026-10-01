//
//  BLAKE2bTests.swift
//  BLAKE2Tests
//

import BLAKE2
import Foundation
import Testing

func hex(_ bytes: [UInt8]) -> String {
    bytes.map { String(format: "%02x", $0) }.joined()
}

func bytes(hex: String) -> [UInt8] {
    var out = [UInt8]()
    var index = hex.startIndex
    while index < hex.endIndex {
        let next = hex.index(index, offsetBy: 2)
        out.append(UInt8(hex[index..<next], radix: 16)!)
        index = next
    }
    return out
}

@Suite("BLAKE2b")
struct BLAKE2bTests {
    @Test("RFC 7693 appendix A: BLAKE2b-512 of \"abc\"")
    func rfcVector() {
        let digest = BLAKE2b.hash(Array("abc".utf8))
        #expect(
            hex(digest)
                == "ba80a53f981c4d0d6a2797b69f12f6e94c212f14685ac4b74b12bb6fdbffa2d17d87c5392aab792dc252d5de4533cc9518d38aa8dbf1925ab92386edd4009923"
        )
    }
}

struct KnownAnswer: Decodable, Sendable {
    let hash: String
    let `in`: String
    let key: String
    let out: String
}

let knownAnswers: [KnownAnswer] = {
    let url = Bundle.module.url(forResource: "blake2b-kat", withExtension: "json", subdirectory: "Fixtures")!
    // swiftlint:disable:next force_try
    return try! JSONDecoder().decode([KnownAnswer].self, from: Data(contentsOf: url))
}()

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

extension BLAKE2bTests {
    @Test("the official known-answer set has keyed and unkeyed entries")
    func knownAnswerSet() {
        #expect(knownAnswers.allSatisfy { $0.hash == "blake2b" })
        #expect(knownAnswers.contains { $0.key.isEmpty })
        #expect(knownAnswers.contains { !$0.key.isEmpty })
        #expect(knownAnswers.count >= 512)
    }

    @Test("every official known answer", arguments: knownAnswers.indices)
    func knownAnswer(index: Int) {
        let vector = knownAnswers[index]
        let digest = BLAKE2b.hash(
            bytes(hex: vector.in), key: bytes(hex: vector.key), digestLength: vector.out.count / 2)
        #expect(
            hex(digest) == vector.out,
            "entry \(index): in \(vector.in.count / 2) bytes, key \(vector.key.count / 2) bytes")
    }

    @Test("streaming in any chunking equals one-shot")
    func streaming() {
        var generator = SplitMix64(seed: 1)
        let message = (0..<1000).map { _ in UInt8.random(in: .min ... .max, using: &generator) }
        let key = (0..<32).map { _ in UInt8.random(in: .min ... .max, using: &generator) }
        let expected = BLAKE2b.hash(message, key: key, digestLength: 32)
        for splits in [
            [0], [1], [63], [64], [65], [127], [128], [129], [255], [256], [257], [500], [999], [1000], [64, 128],
            [1, 127, 128, 129], [128, 256, 384], [128, 128], [64, 64, 64], [0, 500, 500], [128, 128, 128]
        ] {
            var hasher = BLAKE2b(digestLength: 32, key: key)
            var start = 0
            for split in splits {
                hasher.update(message[start..<split])
                start = split
            }
            hasher.update(message[start...])
            #expect(hasher.finalize() == expected, "splits \(splits)")
        }
        var byteAtATime = BLAKE2b(digestLength: 32, key: key)
        for byte in message {
            byteAtATime.update([byte])
        }
        #expect(byteAtATime.finalize() == expected)
    }

    @Test("finalize does not consume the hasher")
    func finalizeIsRepeatable() {
        var hasher = BLAKE2b()
        hasher.update(Array("ab".utf8))
        let ab = hasher.finalize()
        #expect(ab == hasher.finalize())
        hasher.update(Array("c".utf8))
        #expect(hasher.finalize() == BLAKE2b.hash(Array("abc".utf8)))
        #expect(ab != hasher.finalize())
    }

    @Test("messages at and around block boundaries", arguments: [0, 1, 127, 128, 129, 255, 256, 257, 383, 384, 385])
    func blockBoundaries(length: Int) {
        let message = (0..<length).map { UInt8(truncatingIfNeeded: $0 &* 31) }
        var hasher = BLAKE2b()
        for byte in message {
            hasher.update([byte])
        }
        #expect(hasher.finalize() == BLAKE2b.hash(message))
    }

    @Test("known answers at block boundaries", arguments: [0, 1, 127, 128, 129, 255])
    func knownAnswerAtBoundaries(length: Int) throws {
        let entry = try #require(knownAnswers.first { $0.key.isEmpty && $0.in.count == length * 2 })
        #expect(hex(BLAKE2b.hash((0..<length).map { UInt8($0) })) == entry.out)
    }

    @Test("a keyed hash of the empty message treats the key block as the final block")
    func keyedEmptyMessage() throws {
        let keyed = try #require(knownAnswers.first { !$0.key.isEmpty && $0.in.isEmpty })
        #expect(hex(BLAKE2b.hash([], key: bytes(hex: keyed.key))) == keyed.out)
        #expect(hex(BLAKE2b(key: bytes(hex: keyed.key)).finalize()) == keyed.out)
    }

    @Test("the empty unkeyed message matches the known answer")
    func emptyMessage() throws {
        let unkeyed = try #require(knownAnswers.first { $0.key.isEmpty && $0.in.isEmpty })
        #expect(hex(BLAKE2b.hash([])) == unkeyed.out)
    }
}
