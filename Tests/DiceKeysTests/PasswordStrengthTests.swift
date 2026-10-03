//
//  PasswordStrengthTests.swift
//  DiceKeysTests
//

import Derivation
import Testing

@testable import DiceKeys

@Suite("Password strength arithmetic")
struct PasswordStrengthTests {
    @Test("bits are entries times bits per entry, plus a digit for each separator")
    func bits() {
        #expect(Int(PasswordStrength.bits(list: .effLarge, entries: 6, separator: .hyphen)) == 77)
        #expect(Int(PasswordStrength.bits(list: .en512, entries: 15, separator: .hyphen)) == 135)
        #expect(Int(PasswordStrength.bits(list: .lettersDigitsSymbols, entries: 20, separator: .empty)) == 121)
        #expect(Int(PasswordStrength.bits(list: .digits, entries: 6, separator: .empty)) == 19)
        #expect(Int(PasswordStrength.bits(list: .effLarge, entries: 6, separator: .digits)) == 94)
        #expect(Int(PasswordStrength.bits(list: .effLarge, entries: 1, separator: .digits)) == 12)
    }

    @Test("the guaranteed minimum counts whole entries that always fit under a maximum")
    func guaranteedWords() {
        // 6 EFF words, hyphens, longest word 9: prefix-free, so (max + 1) / 10 words fit.
        #expect(
            PasswordStrength.guaranteedEntries(list: .effLarge, entries: 6, separator: .hyphen, maximumCharacters: 16)
                == 1)
        #expect(
            PasswordStrength.guaranteedEntries(list: .effLarge, entries: 6, separator: .hyphen, maximumCharacters: 19)
                == 2)
        #expect(
            PasswordStrength.guaranteedEntries(list: .effLarge, entries: 6, separator: .hyphen, maximumCharacters: 59)
                == 6)
        #expect(
            PasswordStrength.guaranteedEntries(list: .effLarge, entries: 6, separator: .hyphen, maximumCharacters: 999)
                == 6)
        // No separator: 5-letter words on the 512 list, 16 characters hold 3.
        #expect(
            PasswordStrength.guaranteedEntries(list: .en512, entries: 6, separator: .empty, maximumCharacters: 16) == 3)
        // Digit separators are one character each.
        #expect(
            PasswordStrength.guaranteedEntries(list: .en512, entries: 6, separator: .digits, maximumCharacters: 17) == 3
        )
        // Characters count one each.
        #expect(
            PasswordStrength.guaranteedEntries(list: .emoji, entries: 10, separator: .empty, maximumCharacters: 4) == 4)
    }

    @Test("zxcvbn bands by guesses, compared on exact bits")
    func bands() {
        #expect(PasswordStrength.band(bits: 9.9) == .tooGuessable)
        #expect(PasswordStrength.band(bits: 9.97) == .veryGuessable)  // 10^3 is 9.966 bits
        #expect(PasswordStrength.band(bits: 19.93) == .veryGuessable)  // 10^6 is 19.932 bits
        #expect(PasswordStrength.band(bits: 19.94) == .somewhatGuessable)
        #expect(PasswordStrength.band(bits: 26.5) == .somewhatGuessable)  // 10^8 is 26.575 bits
        #expect(PasswordStrength.band(bits: 26.6) == .safelyUnguessable)
        #expect(PasswordStrength.band(bits: 27) == .safelyUnguessable)
        #expect(PasswordStrength.band(bits: 33.2) == .safelyUnguessable)  // 10^10 is 33.219 bits
        #expect(PasswordStrength.band(bits: 33.3) == .veryUnguessable)
        #expect(PasswordStrength.band(bits: 121) == .veryUnguessable)
        #expect(PasswordStrength.Band.veryUnguessable.label == "very unguessable")
        #expect(PasswordStrength.Band.tooGuessable.label == "too guessable")
    }
}
