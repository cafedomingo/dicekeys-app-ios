//
//  FaceSpecification.swift
//  ReadDiceKey
//
//  The DiceKey face specification (lib-dicekey/externally-generated/
//  dicekey-face-specification.{h,cpp}): the 150 faces with their 8-bit underline and
//  overline codes, the physical proportions of a face, and the 11-bit undoverline decoder
//  (lib-read-dicekey/decode-die.cpp). The 150-entry table is transcribed from the C++;
//  the 256-entry code lookups are derived from it at startup (they were verified equal to
//  the C++ tables).
//

import Foundation

/// One of the 150 valid faces: a letter, a digit and the two codes printed under and over it.
/// `.null` (letter and digit 0) stands in for the C++ `NullFaceSpecification`.
struct FaceSpecification: Sendable, Equatable {
    let letter: UInt8
    let digit: UInt8
    let underlineCode: UInt8
    let overlineCode: UInt8

    static let null = FaceSpecification(letter: 0, digit: 0, underlineCode: 0, overlineCode: 0)

    var isNull: Bool { letter == 0 }
}

enum DiceKeyFaceSpecification {
    static let faceLetters = "ABCDEFGHIJKLMNOPRSTUVWXYZ"
    static let faceDigits = "123456"
    static let faceRotationLetters = "trbl"

    static let numberOfDotsInUndoverline = 11
    static let minNumberOfBlackDotsInUndoverline = 4
    static let minNumberOfWhiteDotsInUndoverline = 4

    /// `letterIndexTimesSixPlusDigitIndexFaceWithUndoverlineCodes`.
    static let faces: [FaceSpecification] = [
        FaceSpecification(letter: UInt8(ascii: "A"), digit: UInt8(ascii: "1"), underlineCode: 0x7, overlineCode: 0xe9),
        FaceSpecification(letter: UInt8(ascii: "A"), digit: UInt8(ascii: "2"), underlineCode: 0xb, overlineCode: 0xf1),
        FaceSpecification(letter: UInt8(ascii: "A"), digit: UInt8(ascii: "3"), underlineCode: 0xd, overlineCode: 0xe0),
        FaceSpecification(letter: UInt8(ascii: "A"), digit: UInt8(ascii: "4"), underlineCode: 0x16, overlineCode: 0xf2),
        FaceSpecification(letter: UInt8(ascii: "A"), digit: UInt8(ascii: "5"), underlineCode: 0x1a, overlineCode: 0xea),
        FaceSpecification(letter: UInt8(ascii: "A"), digit: UInt8(ascii: "6"), underlineCode: 0x1e, overlineCode: 0xe1),
        FaceSpecification(letter: UInt8(ascii: "B"), digit: UInt8(ascii: "1"), underlineCode: 0x1f, overlineCode: 0xe6),
        FaceSpecification(letter: UInt8(ascii: "B"), digit: UInt8(ascii: "2"), underlineCode: 0x26, overlineCode: 0xc3),
        FaceSpecification(letter: UInt8(ascii: "B"), digit: UInt8(ascii: "3"), underlineCode: 0x27, overlineCode: 0xc4),
        FaceSpecification(letter: UInt8(ascii: "B"), digit: UInt8(ascii: "4"), underlineCode: 0x29, overlineCode: 0xc6),
        FaceSpecification(letter: UInt8(ascii: "B"), digit: UInt8(ascii: "5"), underlineCode: 0x2b, overlineCode: 0xdc),
        FaceSpecification(letter: UInt8(ascii: "B"), digit: UInt8(ascii: "6"), underlineCode: 0x2c, overlineCode: 0xca),
        FaceSpecification(letter: UInt8(ascii: "C"), digit: UInt8(ascii: "1"), underlineCode: 0x2d, overlineCode: 0xcd),
        FaceSpecification(letter: UInt8(ascii: "C"), digit: UInt8(ascii: "2"), underlineCode: 0x2e, overlineCode: 0xd0),
        FaceSpecification(letter: UInt8(ascii: "C"), digit: UInt8(ascii: "3"), underlineCode: 0x31, overlineCode: 0xc9),
        FaceSpecification(letter: UInt8(ascii: "C"), digit: UInt8(ascii: "4"), underlineCode: 0x32, overlineCode: 0xd4),
        FaceSpecification(letter: UInt8(ascii: "C"), digit: UInt8(ascii: "5"), underlineCode: 0x33, overlineCode: 0xd3),
        FaceSpecification(letter: UInt8(ascii: "C"), digit: UInt8(ascii: "6"), underlineCode: 0x34, overlineCode: 0xc5),
        FaceSpecification(letter: UInt8(ascii: "D"), digit: UInt8(ascii: "1"), underlineCode: 0x35, overlineCode: 0xc2),
        FaceSpecification(letter: UInt8(ascii: "D"), digit: UInt8(ascii: "2"), underlineCode: 0x37, overlineCode: 0xd8),
        FaceSpecification(letter: UInt8(ascii: "D"), digit: UInt8(ascii: "3"), underlineCode: 0x39, overlineCode: 0xda),
        FaceSpecification(letter: UInt8(ascii: "D"), digit: UInt8(ascii: "4"), underlineCode: 0x3a, overlineCode: 0xc7),
        FaceSpecification(letter: UInt8(ascii: "D"), digit: UInt8(ascii: "5"), underlineCode: 0x3b, overlineCode: 0xc0),
        FaceSpecification(letter: UInt8(ascii: "D"), digit: UInt8(ascii: "6"), underlineCode: 0x3c, overlineCode: 0xd6),
        FaceSpecification(letter: UInt8(ascii: "E"), digit: UInt8(ascii: "1"), underlineCode: 0x3d, overlineCode: 0xd1),
        FaceSpecification(letter: UInt8(ascii: "E"), digit: UInt8(ascii: "2"), underlineCode: 0x3e, overlineCode: 0xcc),
        FaceSpecification(letter: UInt8(ascii: "E"), digit: UInt8(ascii: "3"), underlineCode: 0x3f, overlineCode: 0xcb),
        FaceSpecification(letter: UInt8(ascii: "E"), digit: UInt8(ascii: "4"), underlineCode: 0x45, overlineCode: 0xa6),
        FaceSpecification(letter: UInt8(ascii: "E"), digit: UInt8(ascii: "5"), underlineCode: 0x47, overlineCode: 0xbc),
        FaceSpecification(letter: UInt8(ascii: "E"), digit: UInt8(ascii: "6"), underlineCode: 0x4a, overlineCode: 0xa3),
        FaceSpecification(letter: UInt8(ascii: "F"), digit: UInt8(ascii: "1"), underlineCode: 0x4b, overlineCode: 0xa4),
        FaceSpecification(letter: UInt8(ascii: "F"), digit: UInt8(ascii: "2"), underlineCode: 0x4c, overlineCode: 0xb2),
        FaceSpecification(letter: UInt8(ascii: "F"), digit: UInt8(ascii: "3"), underlineCode: 0x4d, overlineCode: 0xb5),
        FaceSpecification(letter: UInt8(ascii: "F"), digit: UInt8(ascii: "4"), underlineCode: 0x4e, overlineCode: 0xa8),
        FaceSpecification(letter: UInt8(ascii: "F"), digit: UInt8(ascii: "5"), underlineCode: 0x51, overlineCode: 0xb1),
        FaceSpecification(letter: UInt8(ascii: "F"), digit: UInt8(ascii: "6"), underlineCode: 0x52, overlineCode: 0xac),
        FaceSpecification(letter: UInt8(ascii: "G"), digit: UInt8(ascii: "1"), underlineCode: 0x53, overlineCode: 0xab),
        FaceSpecification(letter: UInt8(ascii: "G"), digit: UInt8(ascii: "2"), underlineCode: 0x55, overlineCode: 0xba),
        FaceSpecification(letter: UInt8(ascii: "G"), digit: UInt8(ascii: "3"), underlineCode: 0x56, overlineCode: 0xa7),
        FaceSpecification(letter: UInt8(ascii: "G"), digit: UInt8(ascii: "4"), underlineCode: 0x57, overlineCode: 0xa0),
        FaceSpecification(letter: UInt8(ascii: "G"), digit: UInt8(ascii: "5"), underlineCode: 0x58, overlineCode: 0xa5),
        FaceSpecification(letter: UInt8(ascii: "G"), digit: UInt8(ascii: "6"), underlineCode: 0x59, overlineCode: 0xa2),
        FaceSpecification(letter: UInt8(ascii: "H"), digit: UInt8(ascii: "1"), underlineCode: 0x5b, overlineCode: 0xb8),
        FaceSpecification(letter: UInt8(ascii: "H"), digit: UInt8(ascii: "2"), underlineCode: 0x5c, overlineCode: 0xae),
        FaceSpecification(letter: UInt8(ascii: "H"), digit: UInt8(ascii: "3"), underlineCode: 0x5d, overlineCode: 0xa9),
        FaceSpecification(letter: UInt8(ascii: "H"), digit: UInt8(ascii: "4"), underlineCode: 0x5e, overlineCode: 0xb4),
        FaceSpecification(letter: UInt8(ascii: "H"), digit: UInt8(ascii: "5"), underlineCode: 0x5f, overlineCode: 0xb3),
        FaceSpecification(letter: UInt8(ascii: "H"), digit: UInt8(ascii: "6"), underlineCode: 0x62, overlineCode: 0x9d),
        FaceSpecification(letter: UInt8(ascii: "I"), digit: UInt8(ascii: "1"), underlineCode: 0x63, overlineCode: 0x9a),
        FaceSpecification(letter: UInt8(ascii: "I"), digit: UInt8(ascii: "2"), underlineCode: 0x64, overlineCode: 0x8c),
        FaceSpecification(letter: UInt8(ascii: "I"), digit: UInt8(ascii: "3"), underlineCode: 0x65, overlineCode: 0x8b),
        FaceSpecification(letter: UInt8(ascii: "I"), digit: UInt8(ascii: "4"), underlineCode: 0x66, overlineCode: 0x96),
        FaceSpecification(letter: UInt8(ascii: "I"), digit: UInt8(ascii: "5"), underlineCode: 0x67, overlineCode: 0x91),
        FaceSpecification(letter: UInt8(ascii: "I"), digit: UInt8(ascii: "6"), underlineCode: 0x68, overlineCode: 0x94),
        FaceSpecification(letter: UInt8(ascii: "J"), digit: UInt8(ascii: "1"), underlineCode: 0x69, overlineCode: 0x93),
        FaceSpecification(letter: UInt8(ascii: "J"), digit: UInt8(ascii: "2"), underlineCode: 0x6a, overlineCode: 0x8e),
        FaceSpecification(letter: UInt8(ascii: "J"), digit: UInt8(ascii: "3"), underlineCode: 0x6b, overlineCode: 0x89),
        FaceSpecification(letter: UInt8(ascii: "J"), digit: UInt8(ascii: "4"), underlineCode: 0x6d, overlineCode: 0x98),
        FaceSpecification(letter: UInt8(ascii: "J"), digit: UInt8(ascii: "5"), underlineCode: 0x6e, overlineCode: 0x85),
        FaceSpecification(letter: UInt8(ascii: "J"), digit: UInt8(ascii: "6"), underlineCode: 0x6f, overlineCode: 0x82),
        FaceSpecification(letter: UInt8(ascii: "K"), digit: UInt8(ascii: "1"), underlineCode: 0x70, overlineCode: 0x9b),
        FaceSpecification(letter: UInt8(ascii: "K"), digit: UInt8(ascii: "2"), underlineCode: 0x71, overlineCode: 0x9c),
        FaceSpecification(letter: UInt8(ascii: "K"), digit: UInt8(ascii: "3"), underlineCode: 0x72, overlineCode: 0x81),
        FaceSpecification(letter: UInt8(ascii: "K"), digit: UInt8(ascii: "4"), underlineCode: 0x73, overlineCode: 0x86),
        FaceSpecification(letter: UInt8(ascii: "K"), digit: UInt8(ascii: "5"), underlineCode: 0x74, overlineCode: 0x90),
        FaceSpecification(letter: UInt8(ascii: "K"), digit: UInt8(ascii: "6"), underlineCode: 0x75, overlineCode: 0x97),
        FaceSpecification(letter: UInt8(ascii: "L"), digit: UInt8(ascii: "1"), underlineCode: 0x76, overlineCode: 0x8a),
        FaceSpecification(letter: UInt8(ascii: "L"), digit: UInt8(ascii: "2"), underlineCode: 0x77, overlineCode: 0x8d),
        FaceSpecification(letter: UInt8(ascii: "L"), digit: UInt8(ascii: "3"), underlineCode: 0x78, overlineCode: 0x88),
        FaceSpecification(letter: UInt8(ascii: "L"), digit: UInt8(ascii: "4"), underlineCode: 0x79, overlineCode: 0x8f),
        FaceSpecification(letter: UInt8(ascii: "L"), digit: UInt8(ascii: "5"), underlineCode: 0x7a, overlineCode: 0x92),
        FaceSpecification(letter: UInt8(ascii: "L"), digit: UInt8(ascii: "6"), underlineCode: 0x7b, overlineCode: 0x95),
        FaceSpecification(letter: UInt8(ascii: "M"), digit: UInt8(ascii: "1"), underlineCode: 0x7c, overlineCode: 0x83),
        FaceSpecification(letter: UInt8(ascii: "M"), digit: UInt8(ascii: "2"), underlineCode: 0x7d, overlineCode: 0x84),
        FaceSpecification(letter: UInt8(ascii: "M"), digit: UInt8(ascii: "3"), underlineCode: 0x7e, overlineCode: 0x99),
        FaceSpecification(letter: UInt8(ascii: "M"), digit: UInt8(ascii: "4"), underlineCode: 0x85, overlineCode: 0x6a),
        FaceSpecification(letter: UInt8(ascii: "M"), digit: UInt8(ascii: "5"), underlineCode: 0x87, overlineCode: 0x70),
        FaceSpecification(letter: UInt8(ascii: "M"), digit: UInt8(ascii: "6"), underlineCode: 0x89, overlineCode: 0x72),
        FaceSpecification(letter: UInt8(ascii: "N"), digit: UInt8(ascii: "1"), underlineCode: 0x8b, overlineCode: 0x68),
        FaceSpecification(letter: UInt8(ascii: "N"), digit: UInt8(ascii: "2"), underlineCode: 0x8d, overlineCode: 0x79),
        FaceSpecification(letter: UInt8(ascii: "N"), digit: UInt8(ascii: "3"), underlineCode: 0x8e, overlineCode: 0x64),
        FaceSpecification(letter: UInt8(ascii: "N"), digit: UInt8(ascii: "4"), underlineCode: 0x8f, overlineCode: 0x63),
        FaceSpecification(letter: UInt8(ascii: "N"), digit: UInt8(ascii: "5"), underlineCode: 0x92, overlineCode: 0x60),
        FaceSpecification(letter: UInt8(ascii: "N"), digit: UInt8(ascii: "6"), underlineCode: 0x93, overlineCode: 0x67),
        FaceSpecification(letter: UInt8(ascii: "O"), digit: UInt8(ascii: "1"), underlineCode: 0x94, overlineCode: 0x71),
        FaceSpecification(letter: UInt8(ascii: "O"), digit: UInt8(ascii: "2"), underlineCode: 0x95, overlineCode: 0x76),
        FaceSpecification(letter: UInt8(ascii: "O"), digit: UInt8(ascii: "3"), underlineCode: 0x96, overlineCode: 0x6b),
        FaceSpecification(letter: UInt8(ascii: "O"), digit: UInt8(ascii: "4"), underlineCode: 0x97, overlineCode: 0x6c),
        FaceSpecification(letter: UInt8(ascii: "O"), digit: UInt8(ascii: "5"), underlineCode: 0x98, overlineCode: 0x69),
        FaceSpecification(letter: UInt8(ascii: "O"), digit: UInt8(ascii: "6"), underlineCode: 0x99, overlineCode: 0x6e),
        FaceSpecification(letter: UInt8(ascii: "P"), digit: UInt8(ascii: "1"), underlineCode: 0x9a, overlineCode: 0x73),
        FaceSpecification(letter: UInt8(ascii: "P"), digit: UInt8(ascii: "2"), underlineCode: 0x9b, overlineCode: 0x74),
        FaceSpecification(letter: UInt8(ascii: "P"), digit: UInt8(ascii: "3"), underlineCode: 0x9c, overlineCode: 0x62),
        FaceSpecification(letter: UInt8(ascii: "P"), digit: UInt8(ascii: "4"), underlineCode: 0x9d, overlineCode: 0x65),
        FaceSpecification(letter: UInt8(ascii: "P"), digit: UInt8(ascii: "5"), underlineCode: 0x9e, overlineCode: 0x78),
        FaceSpecification(letter: UInt8(ascii: "P"), digit: UInt8(ascii: "6"), underlineCode: 0xa1, overlineCode: 0x4c),
        FaceSpecification(letter: UInt8(ascii: "R"), digit: UInt8(ascii: "1"), underlineCode: 0xa2, overlineCode: 0x51),
        FaceSpecification(letter: UInt8(ascii: "R"), digit: UInt8(ascii: "2"), underlineCode: 0xa3, overlineCode: 0x56),
        FaceSpecification(letter: UInt8(ascii: "R"), digit: UInt8(ascii: "3"), underlineCode: 0xa5, overlineCode: 0x47),
        FaceSpecification(letter: UInt8(ascii: "R"), digit: UInt8(ascii: "4"), underlineCode: 0xa6, overlineCode: 0x5a),
        FaceSpecification(letter: UInt8(ascii: "R"), digit: UInt8(ascii: "5"), underlineCode: 0xa7, overlineCode: 0x5d),
        FaceSpecification(letter: UInt8(ascii: "R"), digit: UInt8(ascii: "6"), underlineCode: 0xa8, overlineCode: 0x58),
        FaceSpecification(letter: UInt8(ascii: "S"), digit: UInt8(ascii: "1"), underlineCode: 0xaa, overlineCode: 0x42),
        FaceSpecification(letter: UInt8(ascii: "S"), digit: UInt8(ascii: "2"), underlineCode: 0xab, overlineCode: 0x45),
        FaceSpecification(letter: UInt8(ascii: "S"), digit: UInt8(ascii: "3"), underlineCode: 0xac, overlineCode: 0x53),
        FaceSpecification(letter: UInt8(ascii: "S"), digit: UInt8(ascii: "4"), underlineCode: 0xad, overlineCode: 0x54),
        FaceSpecification(letter: UInt8(ascii: "S"), digit: UInt8(ascii: "5"), underlineCode: 0xae, overlineCode: 0x49),
        FaceSpecification(letter: UInt8(ascii: "S"), digit: UInt8(ascii: "6"), underlineCode: 0xaf, overlineCode: 0x4e),
        FaceSpecification(letter: UInt8(ascii: "T"), digit: UInt8(ascii: "1"), underlineCode: 0xb0, overlineCode: 0x57),
        FaceSpecification(letter: UInt8(ascii: "T"), digit: UInt8(ascii: "2"), underlineCode: 0xb1, overlineCode: 0x50),
        FaceSpecification(letter: UInt8(ascii: "T"), digit: UInt8(ascii: "3"), underlineCode: 0xb2, overlineCode: 0x4d),
        FaceSpecification(letter: UInt8(ascii: "T"), digit: UInt8(ascii: "4"), underlineCode: 0xb3, overlineCode: 0x4a),
        FaceSpecification(letter: UInt8(ascii: "T"), digit: UInt8(ascii: "5"), underlineCode: 0xb4, overlineCode: 0x5c),
        FaceSpecification(letter: UInt8(ascii: "T"), digit: UInt8(ascii: "6"), underlineCode: 0xb5, overlineCode: 0x5b),
        FaceSpecification(letter: UInt8(ascii: "U"), digit: UInt8(ascii: "1"), underlineCode: 0xb6, overlineCode: 0x46),
        FaceSpecification(letter: UInt8(ascii: "U"), digit: UInt8(ascii: "2"), underlineCode: 0xb7, overlineCode: 0x41),
        FaceSpecification(letter: UInt8(ascii: "U"), digit: UInt8(ascii: "3"), underlineCode: 0xb8, overlineCode: 0x44),
        FaceSpecification(letter: UInt8(ascii: "U"), digit: UInt8(ascii: "4"), underlineCode: 0xb9, overlineCode: 0x43),
        FaceSpecification(letter: UInt8(ascii: "U"), digit: UInt8(ascii: "5"), underlineCode: 0xba, overlineCode: 0x5e),
        FaceSpecification(letter: UInt8(ascii: "U"), digit: UInt8(ascii: "6"), underlineCode: 0xbb, overlineCode: 0x59),
        FaceSpecification(letter: UInt8(ascii: "V"), digit: UInt8(ascii: "1"), underlineCode: 0xbc, overlineCode: 0x4f),
        FaceSpecification(letter: UInt8(ascii: "V"), digit: UInt8(ascii: "2"), underlineCode: 0xbd, overlineCode: 0x48),
        FaceSpecification(letter: UInt8(ascii: "V"), digit: UInt8(ascii: "3"), underlineCode: 0xbe, overlineCode: 0x55),
        FaceSpecification(letter: UInt8(ascii: "V"), digit: UInt8(ascii: "4"), underlineCode: 0xc1, overlineCode: 0x34),
        FaceSpecification(letter: UInt8(ascii: "V"), digit: UInt8(ascii: "5"), underlineCode: 0xc2, overlineCode: 0x29),
        FaceSpecification(letter: UInt8(ascii: "V"), digit: UInt8(ascii: "6"), underlineCode: 0xc3, overlineCode: 0x2e),
        FaceSpecification(letter: UInt8(ascii: "W"), digit: UInt8(ascii: "1"), underlineCode: 0xc4, overlineCode: 0x38),
        FaceSpecification(letter: UInt8(ascii: "W"), digit: UInt8(ascii: "2"), underlineCode: 0xc6, overlineCode: 0x22),
        FaceSpecification(letter: UInt8(ascii: "W"), digit: UInt8(ascii: "3"), underlineCode: 0xc7, overlineCode: 0x25),
        FaceSpecification(letter: UInt8(ascii: "W"), digit: UInt8(ascii: "4"), underlineCode: 0xc9, overlineCode: 0x27),
        FaceSpecification(letter: UInt8(ascii: "W"), digit: UInt8(ascii: "5"), underlineCode: 0xca, overlineCode: 0x3a),
        FaceSpecification(letter: UInt8(ascii: "W"), digit: UInt8(ascii: "6"), underlineCode: 0xcb, overlineCode: 0x3d),
        FaceSpecification(letter: UInt8(ascii: "X"), digit: UInt8(ascii: "1"), underlineCode: 0xcc, overlineCode: 0x2b),
        FaceSpecification(letter: UInt8(ascii: "X"), digit: UInt8(ascii: "2"), underlineCode: 0xcd, overlineCode: 0x2c),
        FaceSpecification(letter: UInt8(ascii: "X"), digit: UInt8(ascii: "3"), underlineCode: 0xce, overlineCode: 0x31),
        FaceSpecification(letter: UInt8(ascii: "X"), digit: UInt8(ascii: "4"), underlineCode: 0xcf, overlineCode: 0x36),
        FaceSpecification(letter: UInt8(ascii: "X"), digit: UInt8(ascii: "5"), underlineCode: 0xd0, overlineCode: 0x2f),
        FaceSpecification(letter: UInt8(ascii: "X"), digit: UInt8(ascii: "6"), underlineCode: 0xd1, overlineCode: 0x28),
        FaceSpecification(letter: UInt8(ascii: "Y"), digit: UInt8(ascii: "1"), underlineCode: 0xd2, overlineCode: 0x35),
        FaceSpecification(letter: UInt8(ascii: "Y"), digit: UInt8(ascii: "2"), underlineCode: 0xd3, overlineCode: 0x32),
        FaceSpecification(letter: UInt8(ascii: "Y"), digit: UInt8(ascii: "3"), underlineCode: 0xd4, overlineCode: 0x24),
        FaceSpecification(letter: UInt8(ascii: "Y"), digit: UInt8(ascii: "4"), underlineCode: 0xd5, overlineCode: 0x23),
        FaceSpecification(letter: UInt8(ascii: "Y"), digit: UInt8(ascii: "5"), underlineCode: 0xd6, overlineCode: 0x3e),
        FaceSpecification(letter: UInt8(ascii: "Y"), digit: UInt8(ascii: "6"), underlineCode: 0xd7, overlineCode: 0x39),
        FaceSpecification(letter: UInt8(ascii: "Z"), digit: UInt8(ascii: "1"), underlineCode: 0xd8, overlineCode: 0x3c),
        FaceSpecification(letter: UInt8(ascii: "Z"), digit: UInt8(ascii: "2"), underlineCode: 0xd9, overlineCode: 0x3b),
        FaceSpecification(letter: UInt8(ascii: "Z"), digit: UInt8(ascii: "3"), underlineCode: 0xda, overlineCode: 0x26),
        FaceSpecification(letter: UInt8(ascii: "Z"), digit: UInt8(ascii: "4"), underlineCode: 0xdb, overlineCode: 0x21),
        FaceSpecification(letter: UInt8(ascii: "Z"), digit: UInt8(ascii: "5"), underlineCode: 0xdc, overlineCode: 0x37),
        FaceSpecification(letter: UInt8(ascii: "Z"), digit: UInt8(ascii: "6"), underlineCode: 0xdd, overlineCode: 0x30),
    ]

    /// `underlineCodeToFaceSpecification`: 256 entries, `.null` where no face has the code.
    static let underlineCodeToFace: [FaceSpecification] = {
        var table = [FaceSpecification](repeating: .null, count: 256)
        for face in faces { table[Int(face.underlineCode)] = face }
        return table
    }()

    /// `overlineCodeToFaceSpecification`.
    static let overlineCodeToFace: [FaceSpecification] = {
        var table = [FaceSpecification](repeating: .null, count: 256)
        for face in faces { table[Int(face.overlineCode)] = face }
        return table
    }()

    /// `decodeUndoverlineByte`: never fails, returns `.null` for an invalid code.
    static func decodeUndoverlineByte(isOverline: Bool, _ letterDigitEncodingByte: UInt8) -> FaceSpecification {
        isOverline ? overlineCodeToFace[Int(letterDigitEncodingByte)] : underlineCodeToFace[Int(letterDigitEncodingByte)]
    }
}

/// `FaceDimensionsFractional`: the geometry of a face as fractions of its edge length.
enum FaceDimensionsFractional {
    static let size: Float = 1
    static let center: Float = 0.5
    static let fontSize: Float = 0.741935
    static let undoverlineLength: Float = 1
    static let undoverlineThickness: Float = 0.177419
    static let undoverlineMarginAtLineStartAndEnd: Float = 0.056452
    static let undoverlineDotWidth: Float = 0.080645
    static let centerOfUndoverlineToCenterOfFace: Float = 0.41129
    static let textBaselineY: Float = 0.725806
    static let charWidth: Float = 0.370968
    static let charHeight: Float = 0.488194
    static let spaceBetweenLetterAndDigit: Float = 0.04375
    static let textRegionWidth: Float = 0.785685
    static let textRegionHeight: Float = 0.488194
    /// Where each of the 11 dots sits along an undoverline, as a fraction of its length.
    static let dotCentersAsFractionOfUndoverline: [Float] = [
        0.0967745,
        0.1774195,
        0.2580645,
        0.3387095,
        0.41935449999999996,
        0.4999995,
        0.5806445,
        0.6612894999999999,
        0.7419344999999999,
        0.8225795,
        0.9032244999999999,
    ]
}

/// undoverline.h `undoverlineWidthAsFractionOfLength`.
let undoverlineWidthAsFractionOfLength: Float = FaceDimensionsFractional.undoverlineThickness / FaceDimensionsFractional.undoverlineLength

// MARK: - decode-die.cpp

/// decode-face.h `UndoverlineTypeOrientationAndEncoding`.
struct UndoverlineTypeOrientationAndEncoding: Sendable {
    var isValid = false
    var wasReadInReverseOrder = false
    var isOverline = false
    var letterDigitEncoding: UInt8 = 0
}

/// decode-die.cpp `decodeUndoverline11Bits`. The 11 bits, most significant first, are:
/// bit 10 always 1, bit 9 overline flag, bits 8-1 the letter/digit byte, bit 0 always 0.
/// If the line was read backwards the always-1 bit shows up last instead of first.
func decodeUndoverline11Bits(_ binaryCodingReadForwardOrBackward: UInt32, isVertical: Bool) -> UndoverlineTypeOrientationAndEncoding {
    let firstBitRead = (binaryCodingReadForwardOrBackward >> UInt32(DiceKeyFaceSpecification.numberOfDotsInUndoverline - 1)) == 1
    let lastBitRead = (binaryCodingReadForwardOrBackward & 1) == 1
    if firstBitRead == lastBitRead {
        // Exactly one of the two end bits must be set.
        return UndoverlineTypeOrientationAndEncoding()
    }
    let wasReadInReverseOrder = lastBitRead
    let binaryEncoding = wasReadInReverseOrder
        ? reverseBits(binaryCodingReadForwardOrBackward, 11)
        : binaryCodingReadForwardOrBackward
    let isOverline = ((binaryEncoding >> 9) & 1) == 1
    let letterDigitEncoding = UInt8((binaryEncoding >> 1) & 0xff)
    return UndoverlineTypeOrientationAndEncoding(
        isValid: true,
        wasReadInReverseOrder: wasReadInReverseOrder,
        isOverline: isOverline,
        letterDigitEncoding: letterDigitEncoding
    )
}
