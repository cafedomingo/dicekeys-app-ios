//
//  WordListTests.swift
//  DerivationTests
//

import CryptoKit
import Foundation
import Testing

@testable import Derivation

@Suite("Word lists")
struct WordListTests {
    @Test("every list has its size, kind and longest entry")
    func shapes() {
        #expect(WordList.en512.count == 512 && WordList.en512.kind == .words && WordList.en512.longestWordLength == 5)
        #expect(
            WordList.en1024.count == 1024 && WordList.en1024.kind == .words && WordList.en1024.longestWordLength == 6)
        for list in [WordList.en512, .en1024] {
            #expect(list.words.allSatisfy { $0.allSatisfy(\.isLowercase) }, "\(list)")
        }
        #expect(WordList.effLarge.count == 7776 && WordList.effLarge.kind == .words)
        #expect(WordList.effLarge.longestWordLength == 9)
        #expect(WordList.emoji.count == 512 && WordList.emoji.kind == .characters)
        #expect(WordList.lettersDigitsSymbols.count == 67)
        #expect(WordList.lettersDigits.count == 57)
        #expect(WordList.lettersSymbols.count == 59)
        #expect(WordList.letters.count == 49)
        #expect(WordList.digits.count == 10)
        for list in [WordList.emoji, .lettersDigitsSymbols, .lettersDigits, .lettersSymbols, .letters, .digits] {
            #expect(list.kind == .characters, "\(list)")
            #expect(list.longestWordLength == 1, "\(list)")
            #expect(list.words.allSatisfy { $0.count == 1 }, "\(list)")
        }
        for list in WordList.allCases {
            #expect(Set(list.words).count == list.count, "\(list) has duplicates")
        }
    }

    @Test("the EFF list is the published file")
    func effLarge() {
        let words = WordList.effLarge.words
        #expect(words.first == "abacus")
        #expect(words.last == "zoom")
        #expect(words == words.sorted())
        #expect(words.allSatisfy { (3...9).contains($0.count) })
        #expect(words.allSatisfy { $0.unicodeScalars.allSatisfy { ($0.value >= 97 && $0.value <= 122) || $0 == "-" } })
        #expect(words.filter { $0.contains("-") } == ["drop-down", "felt-tip", "t-shirt", "yo-yo"])
    }

    @Test("the character sets are the literals the format fixes")
    func characterSets() {
        #expect(WordList.letters.words.joined() == "ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz")
        #expect(WordList.lettersDigits.words.joined() == "ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz23456789")
        #expect(WordList.lettersSymbols.words.joined() == "ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz!@#$%&*-_?")
        #expect(
            WordList.lettersDigitsSymbols.words.joined()
                == "ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz23456789!@#$%&*-_?")
        #expect(WordList.digits.words.joined() == "0123456789")
    }

    @Test("the emoji are single code points with emoji presentation")
    func emoji() {
        let words = WordList.emoji.words
        #expect(words.count == 512)
        #expect(words.allSatisfy { $0.unicodeScalars.count == 1 })
        #expect(words.allSatisfy { $0.unicodeScalars.first!.properties.isEmojiPresentation })
        #expect(words.allSatisfy { !$0.unicodeScalars.first!.properties.isEmojiModifier })
    }

    // An entry is chosen by its position, so these digests pin every list's order.
    @Test("the lists are pinned by digest")
    func digests() {
        #expect(digest(WordList.en512.words) == "773113b55c0a6adcf4df3b4b43187f37a2fe7a8a104ce4b2f898bb72d99aa07d")
        #expect(digest(WordList.en1024.words) == "dbf28ffbc01379ca990e2c49158383f4b33ba98c00e306b62033fc866caf7fec")
        #expect(digest(WordList.effLarge.words) == "abae49761b88f3f1ba31ef944bea1f61b795a3cd7e1cfb7d276ed45bf77967ba")
        #expect(digest(WordList.emoji.words) == "2acc84de6b421f968108f2fefa328c2af9464e2f43a1969844ab120d2e954987")
        #expect(
            digest(WordList.lettersDigitsSymbols.words)
                == "6ced8e1e5836dcde85405bde1a77f0d49834567aead5b3a3328b79ccf1b76d09")
    }

    @Test("bits round up to whole entries, exactly, for every list and every bit count")
    func wordsForBits() {
        for list in WordList.allCases {
            // bitLength[w] is the bit length of count^w, w = 1 ... maximumLengthInWords.
            var limbs: [UInt32] = [1]
            var bitLengths = [0]
            for _ in 1...Recipe.maximumLengthInWords {
                var carry: UInt64 = 0
                for i in limbs.indices {
                    let product = UInt64(limbs[i]) * UInt64(list.count) + carry
                    limbs[i] = UInt32(truncatingIfNeeded: product)
                    carry = product >> 32
                }
                if carry > 0 { limbs.append(UInt32(carry)) }
                bitLengths.append((limbs.count - 1) * 32 + (32 - limbs.last!.leadingZeroBitCount))
            }
            // count^w >= 2^bits exactly when count^w has more than `bits` bits.
            var w = 1
            for bits in 1...list.maximumLengthInBits {
                while bitLengths[w] <= bits { w += 1 }
                #expect(list.words(forBits: bits) == w, "\(list) at \(bits) bits")
            }
            #expect(list.words(forBits: list.maximumLengthInBits) == Recipe.maximumLengthInWords, "\(list)")
            // The maximum is the last bit count 1,020 entries reach, so count^1020 has exactly one more bit.
            #expect(bitLengths[Recipe.maximumLengthInWords] == list.maximumLengthInBits + 1, "\(list) maximum")
        }
    }

    @Test("bits per entry and bits for a count")
    func bits() {
        #expect(WordList.en512.bitsPerEntry == 9)
        #expect(WordList.en1024.bitsPerEntry == 10)
        #expect(abs(WordList.effLarge.bitsPerEntry - 12.925) < 0.001)
        #expect(Int(WordList.effLarge.bits(forWords: 6)) == 77)
        #expect(Int(WordList.lettersDigitsSymbols.bits(forWords: 20)) == 121)
        #expect(Int(WordList.digits.bits(forWords: 6)) == 19)
        #expect(WordList.en512.maximumLengthInBits == 9180)
        #expect(WordList.en1024.maximumLengthInBits == 10200)
    }
}

private func digest(_ words: [String]) -> String {
    ReferenceJSON.hex(SHA256.hash(data: Data(words.joined(separator: "\n").utf8)))
}
