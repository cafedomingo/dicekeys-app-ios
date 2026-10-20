//
//  DiceKeyScanModel.swift
//  DiceKeys
//

import DiceKeySpecification
import Foundation
import Observation
import ReadDiceKey

/// Per-frame results from the scanner, published on the main actor. Only the
/// views that read `dice` re-render on every frame.
@MainActor @Observable
final class DiceKeyScanModel {
    private(set) var imageFrameSize: CGSize = .zero
    private(set) var dice: [DieInFrame] = []

    var facesRead: Int { dice.count { $0.face != nil } }

    /// Every die is read but a letter repeats: dice from more than one DiceKey, which can
    /// never finish as one.
    var hasRepeatedLetters: Bool {
        let letters = dice.compactMap(\.face?.letter)
        return letters.count == DiceKey.faceCount && Set(letters).count < DiceKey.faceCount
    }

    /// Set once, when every face of the DiceKey has been read.
    private(set) var completedDiceKey: DiceKey?

    /// About a second of frames without a code before the code in view counts as gone, so
    /// showing it again reads it again. Codes are only looked for on some frames.
    static let framesToForgetACode = 30

    /// The code in view: set when one comes into view, cleared once it has been gone a while.
    private(set) var code: String?
    private var framesWithoutCode = 0

    /// Drops the code at once, such as when the app leaves the foreground: a recovery code
    /// holds the DiceKey.
    func forgetCode() {
        code = nil
    }

    func apply(_ frame: ScannedFrame) {
        if let code = frame.code {
            framesWithoutCode = 0
            if code != self.code { self.code = code }
        } else if code != nil {
            framesWithoutCode += 1
            if framesWithoutCode >= Self.framesToForgetACode { code = nil }
        }
        if imageFrameSize != frame.size {
            imageFrameSize = frame.size
        }
        dice = frame.dice
        guard completedDiceKey == nil, let faces = frame.diceKey else {
            return
        }
        completedDiceKey = DiceKey(faces)
    }
}

extension DiceKey {
    /// The faces the scanner read, rows top to bottom as the camera saw them.
    convenience init(_ scanned: [ScannedFace]) {
        self.init(
            scanned.map { face in
                Face(
                    letter: face.letter, digit: face.digit,
                    orientation: FaceOrientationLetterTrbl.allCases[face.clockwiseTurns])
            })
    }
}
