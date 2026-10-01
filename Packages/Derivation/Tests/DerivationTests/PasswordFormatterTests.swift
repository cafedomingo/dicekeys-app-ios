//
//  PasswordFormatterTests.swift
//  DerivationTests
//

import CryptoKit
import Foundation
import Testing
@testable import Derivation

@Suite("Password words")
struct PasswordFormatterTests {
    @Test("the lists are the vendored ones, in order")
    func lists() {
        #expect(WordList.en512.words.count == 512)
        #expect(WordList.en1024.words.count == 1024)
        #expect(WordList.en512.words.first == "abide")
        #expect(WordList.en512.words.last == "zippy")
        #expect(WordList.en1024.words.first == "abacus")
        #expect(WordList.en1024.words.last == "zoning")
        // The lists are hashed into every password, so this digest pins them.
        #expect(digest(WordList.en512.words) == "773113b55c0a6adcf4df3b4b43187f37a2fe7a8a104ce4b2f898bb72d99aa07d")
        #expect(digest(WordList.en1024.words) == "dbf28ffbc01379ca990e2c49158383f4b33ba98c00e306b62033fc866caf7fec")
        #expect(Set(WordList.en512.words).count == 512)
        #expect(Set(WordList.en1024.words).count == 1024)
        #expect(WordList.en512.words.allSatisfy { $0.count <= 5 && $0.allSatisfy(\.isLowercase) })
        #expect(WordList.en1024.words.allSatisfy { $0.count <= 6 && $0.allSatisfy(\.isLowercase) })
    }

    @Test(
        "every fixture password formats from its derived bytes",
        arguments: fixture.cases.filter { $0.type == "Password" })
    func fixturePasswords(vector: Vector) throws {
        let recipe = try Recipe(json: vector.recipe, type: .password)
        let secret = recipe.hashFunction.derive(
            seed: Array(vector.seed.utf8), info: Array("Password".utf8) + Array(vector.recipe.utf8),
            outputLength: recipe.lengthInBytes)
        #expect(
            PasswordFormatter.password(from: secret, wordList: recipe.wordList, lengthInChars: recipe.lengthInChars)
                == vector.password)
    }

    @Test("the word index is the low bits of each 8-byte block, big-endian")
    func indexing() {
        var secret = [UInt8](repeating: 0, count: 16)
        secret[7] = 1
        secret[14] = 1  // block value 0x01ff
        secret[15] = 0xff
        let expected = "2-" + WordList.en512.words[1].capitalizedFirst + "-" + WordList.en512.words[(256 + 255) % 512]
        #expect(PasswordFormatter.password(from: secret, wordList: .en512, lengthInChars: nil) == expected)
        #expect(
            PasswordFormatter.password(from: secret, wordList: .en1024, lengthInChars: nil) == "2-"
                + WordList.en1024.words[1].capitalizedFirst + "-" + WordList.en1024.words[511])
    }

    @Test("lengthInChars truncates the finished string, prefix included, and never pads")
    func truncation() {
        let secret = [UInt8](repeating: 0, count: 24)
        let full = "3-Abide-abide-abide"
        #expect(PasswordFormatter.password(from: secret, wordList: .en512, lengthInChars: nil) == full)
        #expect(PasswordFormatter.password(from: secret, wordList: .en512, lengthInChars: 1) == "3")
        #expect(PasswordFormatter.password(from: secret, wordList: .en512, lengthInChars: 2) == "3-")
        #expect(PasswordFormatter.password(from: secret, wordList: .en512, lengthInChars: 8) == "3-Abide-")
        #expect(PasswordFormatter.password(from: secret, wordList: .en512, lengthInChars: 100) == full)
    }
}

private func digest(_ words: [String]) -> String {
    SHA256.hash(data: Data(words.joined(separator: "\n").utf8)).map { String(format: "%02x", $0) }.joined()
}

private extension String {
    var capitalizedFirst: String { prefix(1).uppercased() + dropFirst() }
}
