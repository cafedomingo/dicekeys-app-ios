//
//  PasswordFormatterTests.swift
//  DerivationTests
//

import Foundation
import Testing

@testable import Derivation

@Suite("Password words")
struct PasswordFormatterTests {
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

extension String {
    fileprivate var capitalizedFirst: String { prefix(1).uppercased() + dropFirst() }
}
