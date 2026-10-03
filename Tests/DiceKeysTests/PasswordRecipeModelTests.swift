//
//  PasswordRecipeModelTests.swift
//  DiceKeysTests
//

import Derivation
import Testing

@testable import DiceKeys

@MainActor
@Suite("The password sheet's model")
struct PasswordRecipeModelTests {
    @Test("no purpose, no recipe; a purpose derives a preview from the seed")
    func previewFollowsPurpose() throws {
        let model = PasswordRecipeModel(seed: DiceKey.example.toSeed())
        #expect(model.progress == .incomplete)
        #expect(model.preview == nil)
        model.purpose = "x"
        let recipe = try #require(model.progress.recipe)
        #expect(recipe.type == .password)
        #expect(recipe.name == "x")
        let expected = try Password.derive(seed: DiceKey.example.toSeed(), recipe: recipe.recipe).password
        #expect(model.preview == expected)
        #expect(model.preview?.split(separator: "-").count == 6)
    }

    @Test("without a seed there is a recipe but no preview")
    func noSeed() {
        let model = PasswordRecipeModel(seed: nil)
        model.purpose = "x"
        #expect(model.progress.recipe != nil)
        #expect(model.preview == nil)
    }

    @Test("strength follows the choices and hides for a PIN")
    func strength() {
        let model = PasswordRecipeModel(seed: nil)
        #expect(Int(model.bits) == 77)
        #expect(model.scoredBits == model.bits)
        #expect(model.showsStrength)
        #expect(model.guarantee == nil)
        model.choices.maximumCharacters = 16
        #expect(model.guarantee?.entries == 1)
        #expect(model.scoredBits == WordList.effLarge.bitsPerEntry)
        model.choices.kind = .pin
        #expect(!model.showsStrength)
        model.choices.kind = .random
        #expect(Int(model.bits) == 121)
        #expect(model.guarantee == nil)
    }

    @Test("switching to emoji and back keeps the separator and capitalize choices")
    func listSwitchKeepsJoining() {
        let model = PasswordRecipeModel(seed: nil)
        model.purpose = "x"
        model.choices.separator = .digits
        model.choices.capitalize = true
        model.choices.memorableList = .emoji
        #expect(
            model.progress.recipe?.recipe
                == #"{"purpose":"x","lengthInChars":6,"wordList":"EMOJI_512_single_code_point_20261002"}"#)
        model.choices.memorableList = .effLarge
        #expect(
            model.progress.recipe?.recipe
                == #"{"purpose":"x","capitalize":true,"lengthInWords":6,"separator":"digits","wordList":"EFF_large_7776_words_9_chars_max_20160719"}"#
        )
    }

    @Test("the purpose is trimmed and the sequence number is written above 1")
    func purposeAndSequence() {
        let model = PasswordRecipeModel(seed: nil)
        model.purpose = "  x "
        model.sequenceNumber = 3
        model.choices.kind = .pin
        #expect(
            model.progress.recipe?.recipe
                == ##"{"purpose":"x","lengthInChars":6,"wordList":"CHARS_10_digits_20261002","#":3}"##)
    }

    @Test("the guaranteed minimum counts whole words only, not digit separators")
    func guaranteedBitsExcludeDigits() {
        let model = PasswordRecipeModel(seed: nil)
        model.choices.separator = .digits
        model.choices.maximumCharacters = 20
        #expect(model.guarantee?.entries == 2)
        #expect(Int(model.guarantee?.bits ?? 0) == 25)
        #expect(Int(model.scoredBits) == 25)  // two EFF words, digits not counted
    }
}
