//
//  PartialFace.swift
//  DiceKeys
//
//  Created by Stuart Schechter on 2021/01/20.
//

/// A face being entered by hand: any of letter, digit, or orientation may
/// still be missing.
struct PartialFace: Identifiable, Equatable, Sendable {
    var letter: FaceLetter?
    var digit: FaceDigit?
    var orientation: FaceOrientationLetterTrbl = .Top

    let index: Int
    var id: String { String(describing: index) }

    var face: Face? {
        if let faceLetter = letter, let faceDigit = digit {
            return Face(letter: faceLetter, digit: faceDigit, orientationAsLowercaseLetterTrbl: orientation)
        }
        return nil
    }

    init(_ face: Face, index: Int? = nil) {
        self.letter = face.letter
        self.digit = face.digit
        self.orientation = face.orientationAsLowercaseLetterTrbl
        self.index = index ?? 0
    }

    init(letter: FaceLetter? = nil, digit: FaceDigit? = nil, orientation: FaceOrientationLetterTrbl = .Top, index: Int? = nil) {
        self.letter = letter
        self.digit = digit
        self.orientation = orientation
        self.index = index ?? 0
    }
}
