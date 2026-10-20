//
//  PartialFace.swift
//  DiceKeys
//

import DiceKeySpecification

/// A die being typed in: its letter, digit and orientation, each nil until entered.
struct PartialFace: Equatable, Sendable {
    var letter: FaceLetter?
    var digit: FaceDigit?
    var orientation: FaceOrientationLetterTrbl?

    var face: Face? {
        guard let letter, let digit, let orientation else { return nil }
        return Face(letter: letter, digit: digit, orientation: orientation)
    }
}

extension PartialFace {
    init(_ face: Face) {
        self.init(letter: face.letter, digit: face.digit, orientation: face.orientation)
    }
}
