//
//  TypedDiceKeyTests.swift
//  DiceKeyVaultTests
//

import DiceKeySpecification
import Testing

@testable import DiceKeyVault

@MainActor
struct TypedDiceKeyTests {
    private func type(
        _ letter: FaceLetter, _ digit: FaceDigit, _ orientation: FaceOrientationLetterTrbl, into typed: TypedDiceKey
    ) {
        typed.enter(letter: letter)
        typed.enter(digit: digit)
        typed.choose(orientation)
    }

    @Test("each die takes a letter, a digit and which way is up, then the next die starts")
    func steps() {
        let typed = TypedDiceKey()
        #expect(typed.step == .letter)
        typed.enter(letter: .A)
        #expect(typed.step == .digit)
        typed.enter(digit: ._1)
        #expect(typed.step == .orientation)
        #expect(typed.faces[0].face == nil)
        typed.choose(.Right)
        #expect(typed.faces[0].face == Face(letter: .A, digit: ._1, orientation: .Right))
        #expect(typed.selectedIndex == 1)
        #expect(typed.step == .letter)
    }

    @Test("25 dice make a DiceKey with the orientations chosen")
    func completes() throws {
        let typed = TypedDiceKey()
        for (index, letter) in FaceLetters.enumerated() {
            type(letter, FaceDigits[index % FaceDigits.count], FaceOrientationLettersTrbl[index % 4], into: typed)
        }
        let diceKey = try #require(typed.diceKey)
        #expect(diceKey.faces.map(\.letter) == FaceLetters)
        #expect(diceKey.faces[1].orientation == .Right)
    }

    @Test("once every die is in, none is selected, so no key is live until one is tapped")
    func completeSelectsNothing() {
        let typed = TypedDiceKey()
        for (index, letter) in FaceLetters.enumerated() {
            type(letter, FaceDigits[index % FaceDigits.count], .Top, into: typed)
        }
        #expect(typed.selectedIndex == nil)
        #expect(typed.step == nil)
        typed.enter(letter: .Z)
        #expect(typed.diceKey != nil)
    }

    @Test("backspace after the last die reopens its orientation")
    func backspaceAfterComplete() {
        let typed = TypedDiceKey()
        for (index, letter) in FaceLetters.enumerated() {
            type(letter, FaceDigits[index % FaceDigits.count], .Top, into: typed)
        }
        typed.backspace()
        #expect(typed.selectedIndex == DiceKey.faceCount - 1)
        #expect(typed.step == .orientation)
    }

    @Test("a letter on another die can't be typed, but redoing a die frees its own")
    func usedLetters() {
        let typed = TypedDiceKey()
        type(.A, ._1, .Top, into: typed)
        typed.enter(letter: .A)
        #expect(typed.faces[1].letter == nil)
        typed.selectedIndex = 0
        typed.enter(letter: .A)
        #expect(typed.faces[0] == PartialFace(letter: .A))
    }

    @Test("redoing a die goes on to the next die still to type")
    func redo() {
        let typed = TypedDiceKey()
        type(.A, ._1, .Top, into: typed)
        type(.B, ._2, .Top, into: typed)
        typed.selectedIndex = 0
        type(.C, ._3, .Left, into: typed)
        #expect(typed.faces[0].face == Face(letter: .C, digit: ._3, orientation: .Left))
        #expect(typed.selectedIndex == 2)
    }

    @Test("backspace undoes one step, then the previous die's orientation")
    func backspace() {
        let typed = TypedDiceKey()
        type(.A, ._1, .Top, into: typed)
        typed.enter(letter: .B)
        typed.backspace()
        #expect(typed.faces[1] == PartialFace())
        typed.backspace()
        #expect(typed.selectedIndex == 0)
        #expect(typed.faces[0] == PartialFace(letter: .A, digit: ._1))
        #expect(typed.step == .orientation)
    }
}
