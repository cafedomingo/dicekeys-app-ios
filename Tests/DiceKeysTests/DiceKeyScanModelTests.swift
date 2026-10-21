//
//  DiceKeyScanModelTests.swift
//  DiceKeysTests
//

import CoreGraphics
import DiceKeySpecification
import ReadDiceKey
import Testing

@testable import DiceKeys

@MainActor
@Suite("Finishing a scan")
struct DiceKeyScanModelTests {
    private let faces = FaceLetter.allCases.map { ScannedFace(letter: $0, digit: ._1, clockwiseTurns: 0) }

    @Test("the scan finishes once the faces make a DiceKey")
    func finishesOnADiceKey() {
        let model = DiceKeyScanModel()
        model.apply(ScannedFrame(dice: [], size: CGSize(width: 1080, height: 1080), diceKey: nil))
        #expect(model.completedDiceKey == nil)
        model.apply(ScannedFrame(dice: [], size: CGSize(width: 1080, height: 1080), diceKey: faces))
        #expect(model.completedDiceKey?.faces.map(\.letter) == faces.map(\.letter))
    }

    @Test("dice that repeat a letter are reported, and never finish the scan")
    func repeatedLetters() {
        let model = DiceKeyScanModel()
        let repeated = faces.enumerated().map { index, face in
            ScannedFace(letter: index == 1 ? .A : face.letter, digit: face.digit, clockwiseTurns: 0)
        }
        let dice = repeated.map { DieInFrame(center: .zero, angle: 0, size: 1, face: $0) }
        model.apply(ScannedFrame(dice: dice, size: CGSize(width: 1080, height: 1080), diceKey: nil))
        #expect(model.hasRepeatedLetters)
    }

    @Test("a code in view is kept until a different one is seen")
    func code() {
        let model = DiceKeyScanModel()
        let size = CGSize(width: 1080, height: 1080)
        model.apply(ScannedFrame(dice: [], size: size, diceKey: nil, code: "a"))
        #expect(model.code == "a")
        model.apply(ScannedFrame(dice: [], size: size, diceKey: nil))
        #expect(model.code == "a")
        model.apply(ScannedFrame(dice: [], size: size, diceKey: nil, code: "b"))
        #expect(model.code == "b")
    }

    @Test("a code out of view for a while is forgotten, so showing it again reads it again")
    func codeOutOfViewIsForgotten() {
        let model = DiceKeyScanModel()
        let size = CGSize(width: 1080, height: 1080)
        model.apply(ScannedFrame(dice: [], size: size, diceKey: nil, code: "a"))
        for _ in 0..<DiceKeyScanModel.framesToForgetACode {
            model.apply(ScannedFrame(dice: [], size: size, diceKey: nil))
        }
        #expect(model.code == nil)
        model.apply(ScannedFrame(dice: [], size: size, diceKey: nil, code: "a"))
        #expect(model.code == "a")
    }

    @Test("forgetting drops the code at once")
    func forgetCode() {
        let model = DiceKeyScanModel()
        model.apply(ScannedFrame(dice: [], size: CGSize(width: 1080, height: 1080), diceKey: nil, code: "a"))
        model.forgetCode()
        #expect(model.code == nil)
    }
}
