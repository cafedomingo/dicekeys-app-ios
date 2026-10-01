//
//  SyntheticDiceKey.swift
//  ReadDiceKeyTests
//
//  Draws a DiceKey the way the dice are printed: on each white die, a black underline and
//  overline with a white dot for every 1 bit of the line's 11-bit code. There is no letter
//  or digit on the face, so anything the scanner reads here came from the bars.
//

import CoreGraphics
import DiceKeySpecification
import Foundation

@testable import ReadDiceKey

struct SyntheticDiceKey {
    /// The faces in reading order, rows top to bottom.
    let faces: [ScannedFace]

    /// 25 different letters, with digits and turns varied across the grid.
    static let sample = SyntheticDiceKey(
        faces: FaceLetter.allCases.enumerated().map { i, letter in
            ScannedFace(letter: letter, digit: FaceDigit.allCases[(i * 5) % 6], clockwiseTurns: (i * 3) % 4)
        })

    /// The same dice, each with its digit moved on by one: a different key face for face.
    var withOtherDigits: SyntheticDiceKey {
        SyntheticDiceKey(
            faces: faces.map { face in
                ScannedFace(
                    letter: face.letter,
                    digit: FaceDigit.allCases[(FaceDigit.allCases.firstIndex(of: face.digit)! + 1) % 6],
                    clockwiseTurns: face.clockwiseTurns)
            })
    }

    /// The key as it reads after turning the whole box a quarter turn clockwise.
    var turnedClockwise: SyntheticDiceKey {
        SyntheticDiceKey(faces: ReadDiceKey.turnedClockwise(faces).map { $0! })
    }

    /// A copy of the key with the face at `index` replaced.
    func replacingFace(at index: Int, with face: ScannedFace) -> SyntheticDiceKey {
        var faces = self.faces
        faces[index] = face
        return SyntheticDiceKey(faces: faces)
    }

    /// A `side` x `side` frame with the key filling most of it, turned by `rotation` radians,
    /// leaving out the dice at the indexes in `hiding`. The dice at the indexes in
    /// `unreadable` are drawn with an overline that names a different face, so the scanner
    /// finds them but cannot read them.
    func image(side: Int, rotation: Double = 0.05, hiding: Set<Int> = [], unreadable: Set<Int> = []) -> GrayImage {
        let context = CGContext(
            data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: side,
            space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue
        )!
        // Draw in image coordinates: origin top left, y down.
        context.translateBy(x: 0, y: CGFloat(side))
        context.scaleBy(x: 1, y: -1)
        context.setFillColor(gray: 0.12, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: side, height: side))

        let pitch = Double(side) / 6
        let faceSize = pitch * 0.5
        for index in 0..<25 where !hiding.contains(index) {
            let face = faces[index]
            let offset = (x: Double(index % 5 - 2) * pitch, y: Double(index / 5 - 2) * pitch)
            let center = CGPoint(
                x: Double(side) / 2 + offset.x * cos(rotation) - offset.y * sin(rotation),
                y: Double(side) / 2 + offset.x * sin(rotation) + offset.y * cos(rotation)
            )
            context.saveGState()
            context.translateBy(x: center.x, y: center.y)
            context.rotate(by: rotation)
            context.setFillColor(gray: 0.95, alpha: 1)
            context.fill(CGRect(x: -pitch * 0.45, y: -pitch * 0.45, width: pitch * 0.9, height: pitch * 0.9))
            // From here on x runs from the letter to the digit and y points down the face.
            context.rotate(by: Double(face.clockwiseTurns) * .pi / 2)
            let specs = letterIndexTimesSixPlusDigitIndexFaceWithUndoverlineCodes
            let spec = specs.firstIndex { $0.letter == face.letter && $0.digit == face.digit }!
            let overline = specs[unreadable.contains(index) ? (spec + 1) % specs.count : spec].overlineCode
            let lineOffset = faceSize * FaceDimensionsFractional.centerOfUndoverlineToCenterOfFace
            drawLine(
                in: context, code: specs[spec].underlineCode, isOverline: false, centerY: lineOffset, faceSize: faceSize
            )
            drawLine(in: context, code: overline, isOverline: true, centerY: -lineOffset, faceSize: faceSize)
            context.restoreGState()
        }
        let data = context.data!.assumingMemoryBound(to: UInt8.self)
        return GrayImage(width: side, height: side, pixels: Array(UnsafeBufferPointer(start: data, count: side * side)))
    }

    /// One bar: 11 bits from the letter end, a 1, the overline flag, the 8-bit code, a 0.
    private func drawLine(in context: CGContext, code: UInt8, isOverline: Bool, centerY: Double, faceSize: Double) {
        let thickness = faceSize * FaceDimensionsFractional.undoverlineThickness
        context.setFillColor(gray: 0, alpha: 1)
        context.fill(CGRect(x: -faceSize / 2, y: centerY - thickness / 2, width: faceSize, height: thickness))
        let bits = (1 << 10) | ((isOverline ? 1 : 0) << 9) | (Int(code) << 1)
        let dot = faceSize * FaceDimensionsFractional.undoverlineDotWidth
        context.setFillColor(gray: 1, alpha: 1)
        for position in 0..<11 where (bits >> (10 - position)) & 1 == 1 {
            let x = -faceSize / 2 + faceSize * FaceDimensionsFractional.dotCentersAsFractionOfUndoverline[position]
            context.fill(CGRect(x: x - dot / 2, y: centerY - dot / 2, width: dot, height: dot))
        }
    }
}
