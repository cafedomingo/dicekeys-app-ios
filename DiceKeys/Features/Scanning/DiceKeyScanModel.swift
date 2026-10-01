//
//  DiceKeyScanModel.swift
//  DiceKeys
//

import DiceKeySpecification
import Foundation
import Observation
import ReadDiceKey

/// Per-frame results from the scanner, published on the main actor. Only the
/// views that read `frameCount` or `dice` re-render on every frame.
@MainActor @Observable
final class DiceKeyScanModel {
    private(set) var frameCount = 0
    private(set) var imageFrameSize: CGSize = .zero
    private(set) var dice: [DieInFrame] = []

    /// Set once, when every face of the DiceKey has been read.
    private(set) var completedDiceKey: DiceKey?

    /// When checking a copy, any 25 faces finish the scan, a letter repeated and all, so the
    /// check can show which dice were copied wrong. Otherwise they must make a DiceKey.
    private let checkingACopy: Bool

    init(checkingACopy: Bool = false) {
        self.checkingACopy = checkingACopy
    }

    func apply(_ frame: ScannedFrame) {
        frameCount += 1
        if imageFrameSize != frame.size {
            imageFrameSize = frame.size
        }
        dice = frame.dice
        guard completedDiceKey == nil, let faces = checkingACopy ? frame.allFaces : frame.diceKey else {
            return
        }
        completedDiceKey = DiceKey(faces)
    }
}

extension DiceKey {
    /// The faces the scanner read, rows top to bottom as the camera saw them.
    convenience init(_ scanned: [ScannedFace]) {
        self.init(scanned.map { face in
            Face(
                letter: face.letter,
                digit: face.digit,
                orientationAsLowercaseLetterTrbl: FaceOrientationLetterTrbl.allCases[face.clockwiseTurns]
            )
        })
    }
}
