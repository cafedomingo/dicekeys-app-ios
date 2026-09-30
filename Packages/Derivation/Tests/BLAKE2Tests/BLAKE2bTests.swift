//
//  BLAKE2bTests.swift
//  BLAKE2Tests
//

import Foundation
import Testing
import BLAKE2

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
        #expect(hex(digest) == "ba80a53f981c4d0d6a2797b69f12f6e94c212f14685ac4b74b12bb6fdbffa2d17d87c5392aab792dc252d5de4533cc9518d38aa8dbf1925ab92386edd4009923")
    }
}
