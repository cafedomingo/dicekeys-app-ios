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
            PasswordFormatter.password(
                from: secret, wordList: recipe.wordList, joining: recipe.joining, lengthInChars: recipe.lengthInChars)
                == vector.password)
    }

    @Test("the word index is the low bits of each 8-byte block, big-endian")
    func indexing() {
        var secret = [UInt8](repeating: 0, count: 16)
        secret[7] = 1
        secret[14] = 1  // block value 0x01ff
        secret[15] = 0xff
        let expected = "2-" + WordList.en512.words[1].capitalizedFirst + "-" + WordList.en512.words[(256 + 255) % 512]
        #expect(
            PasswordFormatter.password(from: secret, wordList: .en512, joining: .reference, lengthInChars: nil)
                == expected)
        #expect(
            PasswordFormatter.password(from: secret, wordList: .en1024, joining: .reference, lengthInChars: nil)
                == "2-"
                + WordList.en1024.words[1].capitalizedFirst + "-" + WordList.en1024.words[511])
    }

    @Test("lengthInChars truncates the finished string, prefix included, and never pads")
    func truncation() {
        let secret = [UInt8](repeating: 0, count: 24)
        let full = "3-Abide-abide-abide"
        #expect(
            PasswordFormatter.password(from: secret, wordList: .en512, joining: .reference, lengthInChars: nil) == full
        )
        #expect(
            PasswordFormatter.password(from: secret, wordList: .en512, joining: .reference, lengthInChars: 1) == "3")
        #expect(
            PasswordFormatter.password(from: secret, wordList: .en512, joining: .reference, lengthInChars: 2) == "3-")
        #expect(
            PasswordFormatter.password(from: secret, wordList: .en512, joining: .reference, lengthInChars: 8)
                == "3-Abide-")
        #expect(
            PasswordFormatter.password(from: secret, wordList: .en512, joining: .reference, lengthInChars: 100) == full
        )
    }

    @Test("modern joining drops the count, joins by the separator and stays lowercase")
    func modernSeparators() {
        let secret = blocks([0, 1, 2])  // abide, acorn, acts on the 512 list
        func join(_ separator: Separator) -> String {
            PasswordFormatter.password(
                from: secret, wordList: .en512, joining: .modern(separator: separator, capitalize: false),
                lengthInChars: nil)
        }
        #expect(join(.hyphen) == "abide-acorn-acts")
        #expect(join(.space) == "abide acorn acts")
        #expect(join(.period) == "abide.acorn.acts")
        #expect(join(.comma) == "abide,acorn,acts")
        #expect(join(.underscore) == "abide_acorn_acts")
        #expect(join(.empty) == "abideacornacts")
    }

    @Test("a digit separator is the preceding block's quotient modulo 10")
    func digitSeparators() {
        // Block 512 * 17 + 0 picks word 0 with quotient 17 -> digit 7; 512 * 3 + 1 picks word 1, quotient 3.
        let secret = blocks([512 * 17, 512 * 3 + 1, 2])
        let password = PasswordFormatter.password(
            from: secret, wordList: .en512, joining: .modern(separator: .digits, capitalize: false), lengthInChars: nil
        )
        #expect(password == "abide7acorn3acts")
        let single = PasswordFormatter.password(
            from: blocks([512 * 17]), wordList: .en512, joining: .modern(separator: .digits, capitalize: false),
            lengthInChars: nil)
        #expect(single == "abide")
    }

    @Test("capitalize uppercases the one word the last block's quotient picks")
    func capitalize() {
        // Last block 512 * 4 + 2: word 2, quotient 4, 4 mod 3 words = index 1.
        let secret = blocks([0, 1, 512 * 4 + 2])
        let password = PasswordFormatter.password(
            from: secret, wordList: .en512, joining: .modern(separator: .hyphen, capitalize: true), lengthInChars: nil)
        #expect(password == "abide-ACORN-acts")
        let one = PasswordFormatter.password(
            from: blocks([512 * 4]), wordList: .en512, joining: .modern(separator: .hyphen, capitalize: true),
            lengthInChars: nil)
        #expect(one == "ABIDE")
        let withDigits = PasswordFormatter.password(
            from: blocks([512 * 17, 512 * 3 + 1, 512 * 4 + 2]), wordList: .en512,
            joining: .modern(separator: .digits, capitalize: true), lengthInChars: nil)
        #expect(withDigits == "abide7ACORN3acts")
    }

    @Test("the words are the same under every joining")
    func wordsAgree() {
        let secret = blocks([512 * 17 + 5, 512 * 3 + 300, 512 * 9 + 511, 7])
        let reference = PasswordFormatter.password(
            from: secret, wordList: .en512, joining: .reference, lengthInChars: nil)
        let modern = PasswordFormatter.password(
            from: secret, wordList: .en512, joining: .modern(separator: .hyphen, capitalize: false), lengthInChars: nil
        )
        #expect(reference.lowercased() == "4-" + modern)
        let entries = PasswordFormatter.entries(from: secret, wordList: .en512)
        #expect(
            entries.map(\.word) == [
                WordList.en512.words[5], WordList.en512.words[300], WordList.en512.words[511], WordList.en512.words[7]
            ])
        #expect(entries.map(\.quotient) == [17, 3, 9, 0])
    }

    @Test("character sets concatenate, and emoji count one each when truncated")
    func characters() {
        let secret = blocks([0, 1, 9, 66])  // A, B, j... on the 67 set: indices into the literal
        let password = PasswordFormatter.password(
            from: secret, wordList: .lettersDigitsSymbols, joining: .modern(separator: .empty, capitalize: false),
            lengthInChars: nil)
        #expect(password == "AB" + WordList.lettersDigitsSymbols.words[9] + "?")
        let pin = PasswordFormatter.password(
            from: blocks([0, 10, 29]), wordList: .digits, joining: .modern(separator: .empty, capitalize: false),
            lengthInChars: nil)
        #expect(pin == "009")
        let emoji = PasswordFormatter.password(
            from: blocks([0, 1, 2]), wordList: .emoji, joining: .modern(separator: .empty, capitalize: false),
            lengthInChars: 2)
        #expect(emoji == WordList.emoji.words[0] + WordList.emoji.words[1])
    }

    @Test("lengthInChars truncates a modern password after its words are joined")
    func modernTruncation() {
        let password = PasswordFormatter.password(
            from: blocks([0, 1, 2]), wordList: .en512, joining: .modern(separator: .hyphen, capitalize: false),
            lengthInChars: 5)
        #expect(password == "abide")
        let seven = PasswordFormatter.password(
            from: blocks([0, 1, 2]), wordList: .en512, joining: .modern(separator: .hyphen, capitalize: false),
            lengthInChars: 7)
        #expect(seven == "abide-a")
    }
}

extension String {
    fileprivate var capitalizedFirst: String { prefix(1).uppercased() + dropFirst() }
}

/// 8-byte big-endian blocks from the given values.
private func blocks(_ values: [UInt64]) -> [UInt8] {
    values.flatMap { value in (0..<8).map { UInt8(truncatingIfNeeded: value >> (8 * (7 - $0))) } }
}
