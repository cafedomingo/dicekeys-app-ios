//
//  SyntheticDiceKey.swift
//  ReadDiceKeyTests
//
//  Draws a DiceKey the way the dice are printed: on each white die, a black underline and
//  overline with a white dot for every 1 bit of the line's 11-bit code, and, when asked, the
//  letter and digit between them. Without them, anything the scanner reads came from the bars.
//

import CoreGraphics
import CoreText
import DiceKeySpecification
import Foundation
import simd

@testable import ReadDiceKey

struct SyntheticDiceKey {
    /// The gray around the dice.
    private static let background = 0.12
    /// The gray of an overline washed out: too near the die's white to be told from it, though
    /// its dots still read.
    private static let washedOutBar = 0.93

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

    /// A `side` x `side` frame with the key filling most of it, turned by `rotation` radians and
    /// moved by `offset` pixels, leaving out the dice at the indexes in `hiding`. The dice at the
    /// indexes in `unreadable` are drawn with an overline that names a different face, so their
    /// bars cannot be read. The dice at the indexes in `washedOut` have their overline drawn so
    /// pale that it is not found as a bar, though reading it where the grid puts it still works.
    /// Each die shows the letter and digit `printing` gives for it, if any.
    /// The `strays` are more dice, at positions of the grid beyond the key. The `covers` are
    /// drawn over everything in the background's gray, as a finger or the box's wall over a die.
    func image(
        side: Int, rotation: Double = 0.05, offset: CGVector = .zero, hiding: Set<Int> = [],
        unreadable: Set<Int> = [], washedOut: Set<Int> = [], printing: [ScannedFace]? = nil,
        strays: [(column: Int, row: Int, face: ScannedFace)] = [], covers: [CGRect] = []
    ) -> GrayImage {
        let pitch = Double(side) / 6
        let key = faces.indices.filter { !hiding.contains($0) }.map { index in
            (
                column: index % 5, row: index / 5, face: faces[index], readable: !unreadable.contains(index),
                text: printing?[index], washedOut: washedOut.contains(index)
            )
        }
        let dice = key + strays.map { ($0.column, $0.row, $0.face, true, nil, false) }
        return Self.frame(side: side) { context in
            for die in dice {
                let x = Double(die.column - 2) * pitch
                let y = Double(die.row - 2) * pitch
                let center = CGPoint(
                    x: Double(side) / 2 + offset.dx + x * cos(rotation) - y * sin(rotation),
                    y: Double(side) / 2 + offset.dy + x * sin(rotation) + y * cos(rotation)
                )
                drawDie(
                    die.face, in: context, at: center, rotation: rotation, pitch: pitch, readable: die.readable,
                    text: die.text, washedOut: die.washedOut)
            }
            context.setFillColor(gray: Self.background, alpha: 1)
            context.fill(covers)
        }
    }

    /// A `side` x `side` frame with the key's dice scattered across it at all angles, as on a
    /// table, spread out along a sunflower's spiral so that no two touch.
    func scatteredImage(side: Int) -> GrayImage {
        let goldenAngle = Double.pi * (3 - 5.squareRoot())
        return Self.frame(side: side) { context in
            for (i, face) in faces.enumerated() {
                let radius = 0.42 * Double(side) * ((Double(i) + 0.5) / Double(faces.count)).squareRoot()
                let center = CGPoint(
                    x: Double(side) / 2 + radius * cos(Double(i) * goldenAngle),
                    y: Double(side) / 2 + radius * sin(Double(i) * goldenAngle)
                )
                drawDie(
                    face, in: context, at: center, rotation: Double(i) * 0.7, pitch: Double(side) / 10, readable: true,
                    text: nil, washedOut: false)
            }
        }
    }

    /// A `side` x `side` frame of the background, with `draw` drawing on it in image
    /// coordinates: origin top left, y down.
    private static func frame(side: Int, draw: (CGContext) -> Void) -> GrayImage {
        let context = CGContext(
            data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: side,
            space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue
        )!
        context.translateBy(x: 0, y: CGFloat(side))
        context.scaleBy(x: 1, y: -1)
        context.setFillColor(gray: background, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: side, height: side))
        draw(context)
        let data = context.data!.assumingMemoryBound(to: UInt8.self)
        return GrayImage(width: side, height: side, pixels: Array(UnsafeBufferPointer(start: data, count: side * side)))
    }

    /// One die `pitch` * 0.9 across, its face half the pitch, at `center` and turned by `rotation`
    /// radians and then by the face's own turns, after which x runs from the letter to the digit
    /// and y points down the face. An unreadable die's overline names the next face.
    private func drawDie(
        _ face: ScannedFace, in context: CGContext, at center: CGPoint, rotation: Double, pitch: Double,
        readable: Bool, text: ScannedFace?, washedOut: Bool
    ) {
        let faceSize = pitch * 0.5
        context.saveGState()
        context.translateBy(x: center.x, y: center.y)
        context.rotate(by: rotation)
        context.setFillColor(gray: 0.95, alpha: 1)
        context.fill(CGRect(x: -pitch * 0.45, y: -pitch * 0.45, width: pitch * 0.9, height: pitch * 0.9))
        context.rotate(by: Double(face.clockwiseTurns) * .pi / 2)
        let specs = letterIndexTimesSixPlusDigitIndexFaceWithUndoverlineCodes
        let spec = specs.firstIndex { $0.letter == face.letter && $0.digit == face.digit }!
        let overline = specs[readable ? spec : (spec + 1) % specs.count].overlineCode
        let lineOffset = faceSize * FaceDimensionsFractional.centerOfUndoverlineToCenterOfFace
        drawLine(
            in: context, code: specs[spec].underlineCode, isOverline: false, centerY: lineOffset, faceSize: faceSize
        )
        drawLine(
            in: context, code: overline, isOverline: true, centerY: -lineOffset, faceSize: faceSize,
            gray: washedOut ? Self.washedOutBar : 0)
        if let text {
            drawText(in: context, text: text, faceSize: faceSize)
        }
        context.restoreGState()
    }

    /// The face's letter and digit, in the font and place they are printed. The context is
    /// flipped for them, since glyphs are drawn with y up.
    private func drawText(in context: CGContext, text: ScannedFace, faceSize: Double) {
        let provider = CGDataProvider(url: PrintedFont.url as CFURL)!
        let font = CTFontCreateWithGraphicsFont(
            CGFont(provider)!, faceSize * FaceDimensionsFractional.fontSize, nil, nil)
        let characters = Array((text.letter.rawValue + text.digit.rawValue).utf16)
        var glyphs = [CGGlyph](repeating: 0, count: characters.count)
        CTFontGetGlyphsForCharacters(font, characters, &glyphs, characters.count)
        let advance =
            (FaceDimensionsFractional.charWidth + FaceDimensionsFractional.spaceBetweenLetterAndDigit) * faceSize
        context.saveGState()
        context.setFillColor(gray: 0, alpha: 1)
        context.translateBy(
            x: -FaceDimensionsFractional.textRegionWidth / 2 * faceSize,
            y: (FaceDimensionsFractional.textBaselineY - 0.5) * faceSize)
        context.scaleBy(x: 1, y: -1)
        CTFontDrawGlyphs(font, glyphs, [.zero, CGPoint(x: advance, y: 0)], glyphs.count, context)
        context.restoreGState()
    }

    /// One bar: 11 bits from the letter end, a 1, the overline flag, the 8-bit code, a 0.
    private func drawLine(
        in context: CGContext, code: UInt8, isOverline: Bool, centerY: Double, faceSize: Double, gray: Double = 0
    ) {
        let thickness = faceSize * FaceDimensionsFractional.undoverlineThickness
        context.setFillColor(gray: gray, alpha: 1)
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

extension GrayImage {
    /// The image as a camera tipped back from it sees it: the top edge narrowed about the middle
    /// to `topWidth` of the bottom edge, in perspective, and the background filling the corners.
    func tilted(topWidth: Double) -> GrayImage {
        let w = Double(width)
        let h = Double(height)
        let inset = (1 - topWidth) / 2 * w
        let fromTilted = squareToQuadrilateral((inset, 0), (w - inset, 0), (w, h), (0, h)).inverse
        var tilted = [UInt8](repeating: pixels[0], count: width * height)
        for y in 0..<height {
            for x in 0..<width {
                let square = fromTilted * SIMD3(Double(x), Double(y), 1)
                let sx = square.x / square.z * w
                let sy = square.y / square.z * h
                let (x0, y0) = (Int(sx.rounded(.down)), Int(sy.rounded(.down)))
                guard x0 >= 0, y0 >= 0, x0 + 1 < width, y0 + 1 < height else { continue }
                let (fx, fy) = (sx - Double(x0), sy - Double(y0))
                let at = { (dx: Int, dy: Int) in Double(pixels[(y0 + dy) * width + x0 + dx]) }
                let top = at(0, 0) * (1 - fx) + at(1, 0) * fx
                let bottom = at(0, 1) * (1 - fx) + at(1, 1) * fx
                tilted[y * width + x] = UInt8((top * (1 - fy) + bottom * fy).rounded())
            }
        }
        return GrayImage(width: width, height: height, pixels: tilted)
    }
}

/// The perspective map from the unit square's corners, clockwise from (0, 0), to the four
/// points given (Heckbert, "Fundamentals of Texture Mapping and Image Warping", 1989).
private func squareToQuadrilateral(
    _ p0: (Double, Double), _ p1: (Double, Double), _ p2: (Double, Double), _ p3: (Double, Double)
) -> simd_double3x3 {
    let (dx1, dy1) = (p1.0 - p2.0, p1.1 - p2.1)
    let (dx2, dy2) = (p3.0 - p2.0, p3.1 - p2.1)
    let (dx3, dy3) = (p0.0 - p1.0 + p2.0 - p3.0, p0.1 - p1.1 + p2.1 - p3.1)
    let determinant = dx1 * dy2 - dx2 * dy1
    let g = (dx3 * dy2 - dx2 * dy3) / determinant
    let h = (dx1 * dy3 - dx3 * dy1) / determinant
    return simd_double3x3(rows: [
        SIMD3(p1.0 - p0.0 + g * p1.0, p3.0 - p0.0 + h * p3.0, p0.0),
        SIMD3(p1.1 - p0.1 + g * p1.1, p3.1 - p0.1 + h * p3.1, p0.1),
        SIMD3(g, h, 1)
    ])
}
