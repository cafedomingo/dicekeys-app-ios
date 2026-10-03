//
//  PasswordRecipeChoicesTests.swift
//  DiceKeysTests
//

import Derivation
import Testing

@testable import DiceKeys

@Suite("The password sheet's recipe")
struct PasswordRecipeChoicesTests {
    private func json(_ choices: PasswordRecipeChoices, sequence: Int = 1) -> String {
        getRecipeJson(purpose: "x", sequenceNumber: sequence, choices: choices)
    }

    @Test("the untouched sheet writes the spec's literals")
    func defaults() {
        #expect(
            json(PasswordRecipeChoices())
                == #"{"purpose":"x","lengthInWords":6,"separator":"-","wordList":"EFF_large_7776_words_9_chars_max_20160719"}"#
        )
        var emoji = PasswordRecipeChoices()
        emoji.memorableList = .emoji
        #expect(json(emoji) == #"{"purpose":"x","lengthInChars":6,"wordList":"EMOJI_512_single_code_point_20261002"}"#)
        var random = PasswordRecipeChoices()
        random.kind = .random
        #expect(
            json(random) == #"{"purpose":"x","lengthInChars":20,"wordList":"CHARS_67_letters_digits_symbols_20261002"}"#
        )
        var pin = PasswordRecipeChoices()
        pin.kind = .pin
        #expect(json(pin) == #"{"purpose":"x","lengthInChars":6,"wordList":"CHARS_10_digits_20261002"}"#)
    }

    @Test("defaults of the format write nothing, and the sequence number goes last")
    func formatDefaults() {
        var choices = PasswordRecipeChoices()
        choices.memorableList = .en512
        choices.wordCount = 15
        #expect(json(choices) == #"{"purpose":"x","separator":"-"}"#)
        #expect(json(choices, sequence: 2) == ##"{"purpose":"x","separator":"-","#":2}"##)
        choices.capitalize = true
        choices.separator = .digits
        choices.maximumCharacters = 20
        #expect(json(choices) == #"{"purpose":"x","capitalize":true,"lengthInChars":20,"separator":"digits"}"#)
    }

    @Test("the random toggles pick among the four letter sets, never an empty one")
    func randomToggles() {
        var choices = PasswordRecipeChoices()
        choices.kind = .random
        #expect(choices.wordList == .lettersDigitsSymbols)
        choices.symbols = false
        #expect(choices.wordList == .lettersDigits)
        choices.numbers = false
        #expect(choices.wordList == .letters)
        choices.symbols = true
        #expect(choices.wordList == .lettersSymbols)
        choices.characterCount = 64
        #expect(json(choices) == #"{"purpose":"x","lengthInChars":64,"wordList":"CHARS_59_letters_symbols_20261002"}"#)
    }

    @Test("a character list writes no joining fields even if the words choices are set")
    func characterListsIgnoreJoining() {
        var choices = PasswordRecipeChoices()
        choices.capitalize = true
        choices.separator = .digits
        choices.maximumCharacters = 20
        choices.memorableList = .emoji
        #expect(
            json(choices) == #"{"purpose":"x","lengthInChars":6,"wordList":"EMOJI_512_single_code_point_20261002"}"#)
        #expect(choices.effectiveSeparator == .empty)
        #expect(choices.entries == 6)
        choices.kind = .pin
        choices.pinLength = 4
        #expect(choices.entries == 4)
        #expect(choices.wordList == .digits)
    }

    @Test("the maximum field ignores values outside 16 to 999 and clears to no limit")
    func maximumEntry() {
        var choices = PasswordRecipeChoices()
        choices.maximumCharactersEntry = 15
        #expect(choices.maximumCharacters == nil)
        choices.maximumCharactersEntry = 16
        #expect(choices.maximumCharacters == 16)
        choices.maximumCharactersEntry = 1000
        #expect(choices.maximumCharacters == 16)
        choices.maximumCharactersEntry = nil
        #expect(choices.maximumCharacters == nil)
    }
}
