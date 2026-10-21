//
//  Face.swift
//  DiceKeyVault
//

import DiceKeySpecification

/// The face of one die as it lies in the box: a letter, a digit, and which way it is turned.
struct Face: Equatable, Sendable {
    let letter: FaceLetter
    let digit: FaceDigit
    let orientation: FaceOrientationLetterTrbl

    /// Letter, digit and orientation, such as `A1t`: the text a Face is stored and typed as.
    var text: String { letter.rawValue + digit.rawValue + orientation.rawValue }

    init(letter: FaceLetter, digit: FaceDigit, orientation: FaceOrientationLetterTrbl) {
        self.letter = letter
        self.digit = digit
        self.orientation = orientation
    }

    init(text: some StringProtocol) throws(DiceKeyFormatError) {
        let characters = Array(text)
        guard characters.count == 3 else { throw .wrongLength(characters.count) }
        guard let letter = FaceLetter(rawValue: String(characters[0])) else { throw .letter(characters[0]) }
        guard let digit = FaceDigit(rawValue: String(characters[1])) else { throw .digit(characters[1]) }
        guard let orientation = FaceOrientationLetterTrbl(rawValue: String(characters[2])) else {
            throw .orientation(characters[2])
        }
        self.init(letter: letter, digit: digit, orientation: orientation)
    }

    /// The same die after a quarter turn of the whole box clockwise.
    var turnedClockwise: Face { Face(letter: letter, digit: digit, orientation: orientation.right) }
}

enum DiceKeyFormatError: Error, Equatable {
    case wrongLength(Int)
    case letter(Character)
    case digit(Character)
    case orientation(Character)
}

extension FaceOrientationLetterTrbl {
    var right: FaceOrientationLetterTrbl {
        switch self {
        case .Top: .Right
        case .Right: .Bottom
        case .Bottom: .Left
        case .Left: .Top
        }
    }

    var clockwiseDegrees: Double {
        switch self {
        case .Top: 0
        case .Right: 90
        case .Bottom: 180
        case .Left: 270
        }
    }

    /// How the face reads aloud: "upright", "right", "down" or "left".
    var spokenDirection: String {
        switch self {
        case .Top: "upright"
        case .Right: "right"
        case .Bottom: "down"
        case .Left: "left"
        }
    }
}
