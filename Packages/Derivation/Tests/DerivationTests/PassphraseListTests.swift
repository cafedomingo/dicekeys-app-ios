//
//  PassphraseListTests.swift
//  DerivationTests
//

import CryptoKit
import Foundation
import Testing

@testable import Derivation

@Suite("Passphrase lists")
struct PassphraseListTests {
    @Test("every list has its size and no duplicates")
    func shapes() {
        #expect(PassphraseList.effLarge.count == 7776)
        #expect(PassphraseList.lettersDigitsSymbols.count == 67)
        #expect(PassphraseList.lettersDigits.count == 57)
        for list in PassphraseList.allCases {
            #expect(Set(list.words).count == list.count, "\(list) has duplicates")
        }
    }

    @Test("the EFF list is the published file")
    func effLarge() {
        let words = PassphraseList.effLarge.words
        #expect(words.first == "abacus")
        #expect(words.last == "zoom")
        #expect(words == words.sorted())
        #expect(words.allSatisfy { (3...9).contains($0.count) })
        #expect(words.allSatisfy { $0.unicodeScalars.allSatisfy { ($0.value >= 97 && $0.value <= 122) || $0 == "-" } })
        #expect(words.filter { $0.contains("-") } == ["drop-down", "felt-tip", "t-shirt", "yo-yo"])
    }

    @Test("the character sets are the literals the format fixes")
    func characterSets() {
        #expect(
            PassphraseList.lettersDigits.words.joined() == "ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz23456789")
        #expect(
            PassphraseList.lettersDigitsSymbols.words.joined()
                == "ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz23456789!@#$%&*-_?")
    }

    // An entry is chosen by its position, so these digests pin every list's order.
    @Test("the lists are pinned by digest")
    func digests() {
        #expect(
            digest(PassphraseList.effLarge.words) == "abae49761b88f3f1ba31ef944bea1f61b795a3cd7e1cfb7d276ed45bf77967ba")
        #expect(
            digest(PassphraseList.lettersDigitsSymbols.words)
                == "6ced8e1e5836dcde85405bde1a77f0d49834567aead5b3a3328b79ccf1b76d09")
    }

    @Test("bits per entry, and a style's strength")
    func bits() {
        #expect(abs(PassphraseList.effLarge.bitsPerEntry - 12.925) < 0.001)
        #expect(Int(PassphraseStyle.memorable(words: 6, digitsAndUppercase: false).bits) == 77)
        #expect(Int(PassphraseStyle.random(length: 20, symbols: true).bits) == 121)
    }
}

private func digest(_ words: [String]) -> String {
    SHA256.hash(data: Data(words.joined(separator: "\n").utf8)).map { String(format: "%02x", $0) }.joined()
}
