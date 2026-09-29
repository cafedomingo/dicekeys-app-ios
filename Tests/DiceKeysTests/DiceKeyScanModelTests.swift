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
    /// 25 faces read in full, the letter A twice, as a copy with a sticker in the wrong place reads.
    private let faces = FaceLetter.allCases.enumerated().map { i, letter in
        ScannedFace(letter: i == 1 ? .A : letter, digit: ._1, clockwiseTurns: 0)
    }

    private var frame: ScannedFrame {
        ScannedFrame(dice: [], size: CGSize(width: 1080, height: 1080), diceKey: nil, allFaces: faces)
    }

    @Test("a key being loaded must have one die per letter")
    func loadingNeedsADiceKey() {
        let model = DiceKeyScanModel()
        model.apply(frame)
        #expect(model.completedDiceKey == nil)
    }

    @Test("a copy being checked finishes on any 25 faces, so its mistakes can be shown")
    func checkingACopyTakesAnyFaces() {
        let model = DiceKeyScanModel(checkingACopy: true)
        model.apply(frame)
        #expect(model.completedDiceKey?.faces.map(\.letter) == faces.map(\.letter))
    }
}
