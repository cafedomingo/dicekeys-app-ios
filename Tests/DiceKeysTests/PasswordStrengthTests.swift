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

    @Test("the bar fills at 80 bits")
    func fill() {
        #expect(PasswordStrength.fill(bits: 0) == 0)
        #expect(PasswordStrength.fill(bits: 40) == 0.5)
        #expect(PasswordStrength.fill(bits: 80) == 1)
        #expect(PasswordStrength.fill(bits: 121) == 1)
    }

    @Test("the color tier turns at 40, 50 and 60 bits")
    func tiers() {
        #expect(PasswordStrength.tier(bits: 39.9) == .weak)
        #expect(PasswordStrength.tier(bits: 40) == .fair)
        #expect(PasswordStrength.tier(bits: 48.5) == .fair)  // 8 random characters
        #expect(PasswordStrength.tier(bits: 50) == .good)
        #expect(PasswordStrength.tier(bits: 59.9) == .good)
        #expect(PasswordStrength.tier(bits: 60) == .strong)
        #expect(PasswordStrength.tier(bits: 77.5) == .strong)  // 6 EFF words
    }
}
