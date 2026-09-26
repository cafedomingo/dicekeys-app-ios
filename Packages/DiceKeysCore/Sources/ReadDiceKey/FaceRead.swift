//
//  FaceRead.swift
//  ReadDiceKey
//
//  A face assembled from its underline, overline and OCR result, and a DiceKey of 25 of
//  them: lib-read-dicekey/face-read.{h,cpp} and lib-dicekey/dicekey.{hpp,cpp} (the parts
//  the scanner uses: error accounting, rotation and merging across frames).
//

import Foundation

/// The ASCII byte for '?', which the C++ uses for an unknown letter, digit or orientation.
let questionMarkByte: UInt8 = 63

// MARK: - face-read.h FaceUndoverlines

/// The underline and overline of one face, with the centre, angle and size they imply.
struct FaceUndoverlines: Sendable {
    var underline = Undoverline()
    var overline = Undoverline()

    init() {}

    init(underline: Undoverline, overline: Undoverline) {
        self.underline = underline
        self.overline = overline
    }

    /// `FaceUndoverlines::center()`. A face with neither line has centre (0, 0), as in the
    /// C++ (its `FaceUndoverlinesCenterOnly` subclass is sliced away when stored).
    func center() -> Point2f {
        if underline.found && overline.found {
            return midpoint2f(midpointOfLine(underline.line), midpointOfLine(overline.line))
        } else if underline.found {
            return underline.inferredCenterOfFace
        } else if overline.found {
            return overline.inferredCenterOfFace
        }
        return .zero
    }

    /// `FaceUndoverlines::inferredAngleInRadians()`.
    func inferredAngleInRadians() -> Float {
        if underline.found && overline.found {
            let lineFromUnderlineCenterToOverlineCenter = Line(start: midpointOfLine(underline.line), end: midpointOfLine(overline.line))
            // The angle of the face is the angle of that line plus 90 degrees clockwise.
            var angleInRadians = angleOfLineInSignedRadians2f(lineFromUnderlineCenterToOverlineCenter) + ninetyDegreesAsRadians
            if angleInRadians > Float(Double.pi) {
                angleInRadians -= Float(2 * Double.pi)
            }
            return angleInRadians
        } else if underline.found {
            return angleOfLineInSignedRadians2f(underline.line)
        } else if overline.found {
            return angleOfLineInSignedRadians2f(overline.line)
        }
        return 0
    }

    /// `FaceUndoverlines::inferredSizeInPixels()` (with the C++ operator precedence kept:
    /// only the overline's length is halved).
    func inferredSizeInPixels() -> Float {
        if underline.found && overline.found {
            return (lineLength(underline.line) + lineLength(overline.line) / 2) / FaceDimensionsFractional.undoverlineLength
        } else if underline.found {
            return lineLength(underline.line) / FaceDimensionsFractional.undoverlineLength
        } else if overline.found {
            return lineLength(overline.line) / FaceDimensionsFractional.undoverlineLength
        }
        return 0
    }
}

// MARK: - face-read.h FaceError

struct FaceError: Sendable, Equatable {
    var magnitude: UInt8
    var location: UInt8

    static let none = FaceError(magnitude: 0, location: 0)
    static let worstPossible = FaceError(magnitude: FaceErrors.Magnitude.max, location: FaceErrors.Location.all)
}

enum FaceErrors {
    enum Location {
        static let underline: UInt8 = 1
        static let overline: UInt8 = 2
        static let ocrLetter: UInt8 = 4
        static let ocrDigit: UInt8 = 8
        static let all: UInt8 = underline + overline + ocrLetter + ocrDigit
    }

    enum Magnitude {
        static let ocrCharacterWasSecondChoice: UInt8 = 2
        static let underlineOrOverlineMissing: UInt8 = 2
        static let ocrCharacterInvalid: UInt8 = 8
        static let max: UInt8 = UInt8.max
    }
}

// MARK: - face-read.{h,cpp} FaceRead

/// One face as read from a frame.
struct FaceRead: Sendable {
    var undoverlines: FaceUndoverlines
    /// 0-3 clockwise turns from upright, or nil for the C++ '?'.
    var orientationAs0to3ClockwiseTurnsFromUpright: Int?
    /// OCR letter candidates, most likely first, as ASCII bytes (empty if the face was not read).
    var ocrLetterFromMostToLeastLikely: [UInt8]
    var ocrDigitFromMostToLeastLikely: [UInt8]

    init() {
        undoverlines = FaceUndoverlines()
        orientationAs0to3ClockwiseTurnsFromUpright = 0
        ocrLetterFromMostToLeastLikely = []
        ocrDigitFromMostToLeastLikely = []
    }

    init(undoverlines: FaceUndoverlines, orientation: Int?, ocrLetters: [UInt8], ocrDigits: [UInt8]) {
        self.undoverlines = undoverlines
        orientationAs0to3ClockwiseTurnsFromUpright = orientation
        ocrLetterFromMostToLeastLikely = ocrLetters
        ocrDigitFromMostToLeastLikely = ocrDigits
    }

    var underline: Undoverline { undoverlines.underline }
    var overline: Undoverline { undoverlines.overline }
    func center() -> Point2f { undoverlines.center() }
    func inferredAngleInRadians() -> Float { undoverlines.inferredAngleInRadians() }
    func inferredSizeInPixels() -> Float { undoverlines.inferredSizeInPixels() }

    /// `FaceRead::rotate`.
    func rotate(_ clockwiseTurnsToRight: Int) -> FaceRead {
        FaceRead(
            undoverlines: undoverlines,
            orientation: orientationAs0to3ClockwiseTurnsFromUpright.map { clockwiseTurnsToRange0To3($0 + clockwiseTurnsToRight) },
            ocrLetters: ocrLetterFromMostToLeastLikely,
            ocrDigits: ocrDigitFromMostToLeastLikely
        )
    }

    var ocrLetterMostLikely: UInt8 { ocrLetterFromMostToLeastLikely.first ?? questionMarkByte }
    var ocrDigitMostLikely: UInt8 { ocrDigitFromMostToLeastLikely.first ?? questionMarkByte }

    /// `FaceRead::letter()`: the value at least two of underline, overline and OCR agree on, else '?'.
    var letter: UInt8 {
        let l = majorityOfThree(underline.faceInferred.letter, overline.faceInferred.letter, ocrLetterMostLikely)
        return l != 0 ? l : questionMarkByte
    }

    /// `FaceRead::digit()`.
    var digit: UInt8 {
        let d = majorityOfThree(underline.faceInferred.digit, overline.faceInferred.digit, ocrDigitMostLikely)
        return d != 0 ? d : questionMarkByte
    }

    /// `IFace::orientationAsLowercaseLetterTRBL()`: 't', 'r', 'b', 'l' or '?'.
    var orientationAsLowercaseLetterTrbl: UInt8 {
        guard let o = orientationAs0to3ClockwiseTurnsFromUpright else { return questionMarkByte }
        return Array(DiceKeyFaceSpecification.faceRotationLetters.utf8)[clockwiseTurnsToRange0To3(o)]
    }

    /// `IFace::isDefined()`.
    var isDefined: Bool {
        letter != questionMarkByte && digit != questionMarkByte && orientationAs0to3ClockwiseTurnsFromUpright != nil
    }

    /// `IFace::equals()`: undefined faces are never equal.
    func equals(_ other: FaceRead) -> Bool {
        isDefined && letter == other.letter && digit == other.digit
            && orientationAs0to3ClockwiseTurnsFromUpright == other.orientationAs0to3ClockwiseTurnsFromUpright
    }

    /// `IFace::toHumanReadableForm(true)`: letter, digit, orientation letter.
    var humanReadableForm: String {
        String(decoding: [letter, digit, orientationAsLowercaseLetterTrbl], as: UTF8.self)
    }

    var errorSize: UInt {
        UInt(error().magnitude)
    }

    /// `FaceRead::error()`: 0 when underline, overline and OCR agree; the hamming distance
    /// of a single wrong undoverline; 2 when OCR's second choice was right; 8 for an OCR
    /// character that matches neither; 255 when nothing reconciles.
    func error() -> FaceError {
        if ocrLetterFromMostToLeastLikely.isEmpty || ocrDigitFromMostToLeastLikely.isEmpty {
            return .worstPossible
        }
        var errorLocation: UInt8 = 0
        var errorMagnitude: UInt = 0
        let ocrLetter0 = ocrLetterMostLikely
        let ocrDigit0 = ocrDigitMostLikely
        let underlineFaceInferred = underline.faceInferred
        let overlineFaceInferred = overline.faceInferred

        // Test the hypothesis of no error: the C++ compares the two FaceSpecification
        // pointers, which is equality of the table entries (or both null).
        if underlineFaceInferred == overlineFaceInferred {
            let undoverlineFaceInferred = underlineFaceInferred
            if undoverlineFaceInferred.letter != ocrLetterMostLikely {
                errorLocation |= FaceErrors.Location.ocrLetter
                errorMagnitude += UInt(
                    ocrLetterFromMostToLeastLikely.count > 1 && undoverlineFaceInferred.letter == ocrLetterFromMostToLeastLikely[1]
                        ? FaceErrors.Magnitude.ocrCharacterWasSecondChoice
                        : FaceErrors.Magnitude.ocrCharacterInvalid
                )
            }
            if undoverlineFaceInferred.digit != ocrDigitMostLikely {
                errorLocation |= FaceErrors.Location.ocrDigit
                errorMagnitude += UInt(
                    ocrDigitFromMostToLeastLikely.count > 1 && undoverlineFaceInferred.digit == ocrDigitFromMostToLeastLikely[1]
                        ? FaceErrors.Magnitude.ocrCharacterWasSecondChoice
                        : FaceErrors.Magnitude.ocrCharacterInvalid
                )
            }
            return FaceError(magnitude: UInt8(min(UInt(UInt8.max), errorMagnitude)), location: errorLocation)
        }
        if underlineFaceInferred.letter == ocrLetter0 && underlineFaceInferred.digit == ocrDigit0 {
            // The underline matches the OCR result, so the error is in the overline.
            return FaceError(
                magnitude: overline.found
                    ? UInt8(hammingDistance(UInt32(underlineFaceInferred.overlineCode), UInt32(overline.letterDigitEncoding)))
                    : FaceErrors.Magnitude.underlineOrOverlineMissing,
                location: FaceErrors.Location.overline
            )
        }
        if overlineFaceInferred.letter == ocrLetter0 && overlineFaceInferred.digit == ocrDigit0 {
            // The overline matches the OCR result, so the error is in the underline.
            return FaceError(
                magnitude: underline.found
                    ? UInt8(hammingDistance(UInt32(overlineFaceInferred.underlineCode), UInt32(underline.letterDigitEncoding)))
                    : FaceErrors.Magnitude.underlineOrOverlineMissing,
                location: FaceErrors.Location.underline
            )
        }
        // No good matching.
        return FaceError(magnitude: UInt8.max, location: UInt8.max)
    }
}

/// face.hpp `clockwiseTurnsToRange0To3`.
@inline(__always)
func clockwiseTurnsToRange0To3(_ clockwiseTurns: Int) -> Int {
    ((clockwiseTurns % 4) + 4) % 4
}

// MARK: - dicekey.{hpp,cpp} DiceKey<FaceRead>

let numberOfFaces = 25

/// dicekey.cpp `rotationIndexes`: for each clockwise rotation, which face moves into each slot.
let rotationIndexes: [[Int]] = [
    [
        0, 1, 2, 3, 4,
        5, 6, 7, 8, 9,
        10, 11, 12, 13, 14,
        15, 16, 17, 18, 19,
        20, 21, 22, 23, 24
    ],
    [
        20, 15, 10, 5, 0,
        21, 16, 11, 6, 1,
        22, 17, 12, 7, 2,
        23, 18, 13, 8, 3,
        24, 19, 14, 9, 4
    ],
    [
        24, 23, 22, 21, 20,
        19, 18, 17, 16, 15,
        14, 13, 12, 11, 10,
        9, 8, 7, 6, 5,
        4, 3, 2, 1, 0
    ],
    [
        4, 9, 14, 19, 24,
        3, 8, 13, 18, 23,
        2, 7, 12, 17, 22,
        1, 6, 11, 16, 21,
        0, 5, 10, 15, 20
    ]
]

/// `DiceKey<FaceRead>`: either uninitialised (no faces) or exactly 25 faces.
struct DiceKeyRead: Sendable {
    var faces: [FaceRead]

    init() {
        faces = []
    }

    init(faces: [FaceRead]) {
        precondition(faces.count == numberOfFaces, "A DiceKey must contain \(numberOfFaces) faces")
        self.faces = faces
    }

    var isInitialized: Bool { faces.count == numberOfFaces }

    var isDefined: Bool {
        isInitialized && faces.allSatisfy { $0.isDefined }
    }

    /// `toHumanReadableForm(true)`.
    var humanReadableForm: String {
        faces.map { $0.humanReadableForm }.joined()
    }

    /// `DiceKey::rotate`.
    func rotate(_ clockwiseTurns: Int) -> DiceKeyRead {
        let clockwiseTurns0to3 = clockwiseTurnsToRange0To3(clockwiseTurns)
        let indexToMoveFaceFrom = rotationIndexes[clockwiseTurns0to3]
        var rotatedFaces: [FaceRead] = []
        rotatedFaces.reserveCapacity(numberOfFaces)
        for i in 0..<numberOfFaces {
            rotatedFaces.append(faces[indexToMoveFaceFrom[i]].rotate(clockwiseTurns0to3))
        }
        return DiceKeyRead(faces: rotatedFaces)
    }

    /// `DiceKey::isPotentialMatch`: more than nine faces match and no two error-free faces disagree.
    func isPotentialMatch(_ other: DiceKeyRead) -> Bool {
        var numMatchingFaces = 0
        for i in 0..<numberOfFaces {
            if faces[i].equals(other.faces[i]) {
                numMatchingFaces += 1
            } else if other.faces[i].errorSize == 0 && faces[i].errorSize == 0 {
                // Two faces both read without error yet different: a different grid, rotation
                // or an undetected error, so the whole key is treated as different.
                return false
            }
        }
        return numMatchingFaces > 9
    }

    /// `DiceKey::mergePrevious`: takes each face from whichever of the two scans read it with
    /// fewer errors, after finding the rotation in which the previous scan matches this one.
    func mergePrevious(_ previous: DiceKeyRead) -> DiceKeyRead {
        if isPotentialMatch(previous) {
            var newFaces: [FaceRead] = []
            newFaces.reserveCapacity(numberOfFaces)
            for i in 0..<numberOfFaces {
                let face = faces[i]
                let previousFace = previous.faces[i]
                newFaces.append(
                    (!previousFace.isDefined || (face.isDefined && face.errorSize <= previousFace.errorSize)) ? face : previousFace
                )
            }
            return DiceKeyRead(faces: newFaces)
        } else {
            for clockwiseTurns in 1..<4 {
                let rotatedKey = previous.rotate(clockwiseTurns)
                if isPotentialMatch(rotatedKey) {
                    return mergePrevious(rotatedKey)
                }
            }
            return DiceKeyRead(faces: faces)
        }
    }

    /// `DiceKey::totalError`: the sum of face errors, or UInt.max when uninitialised.
    var totalError: UInt {
        if !isInitialized {
            return UInt(UInt32.max)
        }
        return faces.reduce(UInt(0)) { $0 + $1.errorSize }
    }

    /// `DiceKey::maxError`.
    var maxError: UInt {
        if !isInitialized {
            return UInt(UInt32.max)
        }
        return faces.reduce(UInt(0)) { max($0, $1.errorSize) }
    }
}
