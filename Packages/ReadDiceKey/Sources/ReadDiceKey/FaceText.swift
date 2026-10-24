//
//  FaceText.swift
//  ReadDiceKey
//
//  Reading a die's printed letter and digit, to settle a face whose two bars do not agree or
//  whose second bar was not found. See docs/scanning.md.
//

import Accelerate
import CoreGraphics
import CoreText
import DiceKeySpecification
import Foundation
import simd

/// Samples across a face, in the grid its text is compared in.
private let gridWidth = 48
/// The band of a face between its bars that holds the text, as fractions of its height.
private let textBand: ClosedRange<Float> = 0.22...0.78
private let firstRow = Int((textBand.lowerBound * Float(gridWidth)).rounded())
private let gridHeight = Int((textBand.upperBound * Float(gridWidth)).rounded()) - firstRow
private let samplesPerText = gridWidth * gridHeight
/// How many samples either way the comparison shifts, to allow for error in the die's center.
private let maxShift = 3
private let shiftsPerAxis = 2 * maxShift + 1

/// How clearly a face's text must be read to settle it: its correlation with the best face, and
/// how far that is ahead of the next face and of the best face at any other quarter turn.
private let minimumScore: Float = 0.7
private let minimumLeadOverOtherFaces: Float = 0.03
private let minimumLeadOverOtherTurns: Float = 0.15
/// The most uncertain a predicted size may be, in variances of one die's measured size.
private let maximumSizeVariance: Float = 1

private let everyFace = letterIndexTimesSixPlusDigitIndexFaceWithUndoverlineCodes

/// The text of every face as the grid of samples it is compared in, zero mean and unit length,
/// one column per face: `samplesPerText` rows of `everyFace.count`, as `vDSP_mmul` takes them.
/// Each face is drawn one pixel per sample, with its baseline measured from the bottom, as
/// CoreGraphics draws.
private let faceTexts: [Float] = {
    let side = gridWidth
    guard let provider = CGDataProvider(url: PrintedFont.url as CFURL), let cgFont = CGFont(provider),
        let context = CGContext(
            data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: side,
            space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue),
        let pixels = context.data?.assumingMemoryBound(to: UInt8.self)
    else { preconditionFailure("cannot draw the faces from the font printed on the dice") }
    let font = CTFontCreateWithGraphicsFont(cgFont, CGFloat(side) * FaceDimensionsFractional.fontSize, nil, nil)
    let letterX = (1 - FaceDimensionsFractional.textRegionWidth) / 2 * CGFloat(side)
    let letterToDigit = FaceDimensionsFractional.charWidth + FaceDimensionsFractional.spaceBetweenLetterAndDigit
    let digitX = letterX + letterToDigit * CGFloat(side)
    let baseline = (1 - FaceDimensionsFractional.textBaselineY) * CGFloat(side)
    let positions = [CGPoint(x: letterX, y: baseline), CGPoint(x: digitX, y: baseline)]

    var texts = [Float](repeating: 0, count: samplesPerText * everyFace.count)
    for (column, face) in everyFace.enumerated() {
        let characters = Array((face.letter.rawValue + face.digit.rawValue).utf16)
        var glyphs = [CGGlyph](repeating: 0, count: characters.count)
        CTFontGetGlyphsForCharacters(font, characters, &glyphs, characters.count)
        context.setFillColor(gray: 1, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: side, height: side))
        context.setFillColor(gray: 0, alpha: 1)
        CTFontDrawGlyphs(font, glyphs, positions, glyphs.count, context)

        let text = (0..<samplesPerText).map { Float(pixels[firstRow * side + $0]) }
        for (sample, value) in normalized(text).enumerated() {
            texts[sample * everyFace.count + column] = value
        }
    }
    return texts
}()

/// The slots, with each face whose bars disagree or whose second bar is missing settled by its
/// printed text when:
/// - the face its text reads best is one a bar names, so the text is only ever a second vote;
/// - it reads clearly, ahead of every other face and of the best face at any other quarter turn;
/// - it reads the same at the size the other dice predict for it, since a die whose bars did not
///   read may be measured wrong, and at a wrong size text can read as another face;
/// - its letter is read on no other die, by bars or by text, since a key has one die per letter.
func settlingFacesByText(_ slots: [Slot], in image: GrayImage) -> [Slot] {
    guard let sizes = SizePlane(fittedTo: slots) else { return slots }
    var candidates: [(index: Int, face: FaceWithUnderlineAndOverlineCode)] = []
    for index in slots.indices where slots[index].face == nil {
        if let expectedSize = sizes.size(at: index),
            let face = image.faceReadFromText(of: slots[index], expectedSize: expectedSize)
        {
            candidates.append((index, face))
        }
    }
    let lettersReadByBars = Set(slots.compactMap { $0.face?.letter })
    let candidatesPerLetter = Dictionary(candidates.map { ($0.face.letter, 1) }, uniquingKeysWith: +)
    var settled = slots
    for (index, face) in candidates
    where !lettersReadByBars.contains(face.letter) && candidatesPerLetter[face.letter] == 1 {
        settled[index].faceFromText = face
    }
    return settled
}

/// The size of the dice across the key, fitted as a plane over rows and columns to the dice whose
/// bars agree, since perspective changes it smoothly.
private struct SizePlane {
    private let inverseNormal: simd_float3x3
    private let coefficients: SIMD3<Float>

    init?(fittedTo slots: [Slot]) {
        var normal = simd_float3x3()
        var moments = SIMD3<Float>()
        for (index, slot) in slots.enumerated() where slot.face != nil {
            guard let size = slot.size else { continue }
            let x = Self.position(index)
            normal += simd_float3x3(x * x.x, x * x.y, x * x.z)
            moments += x * size
        }
        guard normal.determinant != 0 else { return nil }
        inverseNormal = normal.inverse
        coefficients = inverseNormal * moments
    }

    /// The size predicted at slot `index`, unless the prediction is too uncertain, as it is far
    /// from the few dice that agree in a sparse frame.
    func size(at index: Int) -> Float? {
        let x = Self.position(index)
        return simd_dot(x, inverseNormal * x) <= maximumSizeVariance ? simd_dot(coefficients, x) : nil
    }

    private static func position(_ index: Int) -> SIMD3<Float> {
        let (row, column) = index.quotientAndRemainder(dividingBy: 5)
        return SIMD3(1, Float(row), Float(column))
    }
}

extension GrayImage {
    /// The face the slot's text reads, if it passes every rule of `settlingFacesByText` but the
    /// letter, which needs the other dice.
    fileprivate func faceReadFromText(of slot: Slot, expectedSize: Float) -> FaceWithUnderlineAndOverlineCode? {
        guard let center = slot.center, let angle = slot.angle, let size = slot.size else { return nil }
        let scores = faceTextScores(center: center, angle: angle, size: size)
        let ranked = scores.indices.sorted { scores[$0] > scores[$1] }
        let face = everyFace[ranked[0]]
        let score = scores[ranked[0]]
        guard [slot.underline, slot.overline].contains(where: { $0?.bits.face?.underlineCode == face.underlineCode }),
            score >= minimumScore, score - scores[ranked[1]] >= minimumLeadOverOtherFaces
        else { return nil }
        let atExpectedSize = faceTextScores(center: center, angle: angle, size: expectedSize)
        guard atExpectedSize.indices.max(by: { atExpectedSize[$0] < atExpectedSize[$1] }) == ranked[0] else {
            return nil
        }
        let bestAtOtherTurns = [Float.pi / 2, .pi, -.pi / 2].map {
            faceTextScores(center: center, angle: angle + $0, size: size).max() ?? -1
        }
        return score - (bestAtOtherTurns.max() ?? -1) >= minimumLeadOverOtherTurns ? face : nil
    }

    /// For each face, the best correlation of its text with the die's at `center`, `size`
    /// pixels across and reading along `angle`, over shifts of up to `maxShift` samples. Each
    /// shift is one row of windows: the part of the sampled patch that shift lines up with.
    fileprivate func faceTextScores(center: Point, angle: Float, size: Float) -> [Float] {
        let across = Point(angle: angle)
        let down = across.turnedClockwise
        let step = size / Float(gridWidth)
        let patchWidth = gridWidth + 2 * maxShift
        let patchHeight = gridHeight + 2 * maxShift
        let origin = center - (across + down) * (size / 2)
        let patch = (0..<patchHeight).flatMap { row in
            (0..<patchWidth).map { column in
                let u = Float(column - maxShift) + 0.5
                let v = Float(row - maxShift + firstRow) + 0.5
                return bilinear(at: origin + (across * u + down * v) * step)
            }
        }

        let shifts = shiftsPerAxis * shiftsPerAxis
        var windows: [Float] = []
        windows.reserveCapacity(shifts * samplesPerText)
        for dy in 0..<shiftsPerAxis {
            for dx in 0..<shiftsPerAxis {
                let window = (0..<gridHeight).flatMap { row in
                    patch[((row + dy) * patchWidth + dx)...].prefix(gridWidth)
                }
                windows += normalized(window)
            }
        }
        var correlations = [Float](repeating: 0, count: shifts * everyFace.count)
        vDSP_mmul(
            windows, 1, faceTexts, 1, &correlations, 1,
            vDSP_Length(shifts), vDSP_Length(everyFace.count), vDSP_Length(samplesPerText))
        var best = [Float](repeating: -1, count: everyFace.count)
        for (index, correlation) in correlations.enumerated() {
            best[index % everyFace.count] = max(best[index % everyFace.count], correlation)
        }
        return best
    }

    /// The brightness at `point`, interpolated between the four nearest pixels, edges extended.
    /// Pixel (x, y) covers x to x + 1 and y to y + 1, as the bars' outlines do.
    fileprivate func bilinear(at point: Point) -> Float {
        let x = point.x - 0.5
        let y = point.y - 0.5
        let x0 = Int(x.rounded(.down))
        let y0 = Int(y.rounded(.down))
        let fx = x - Float(x0)
        let fy = y - Float(y0)
        func pixel(_ x: Int, _ y: Int) -> Float {
            Float(pixels[min(max(y, 0), height - 1) * width + min(max(x, 0), width - 1)])
        }
        let top = pixel(x0, y0) * (1 - fx) + pixel(x0 + 1, y0) * fx
        let bottom = pixel(x0, y0 + 1) * (1 - fx) + pixel(x0 + 1, y0 + 1) * fx
        return top * (1 - fy) + bottom * fy
    }
}

/// The values less their mean, scaled to unit length, so that a dot product is a correlation.
private func normalized(_ values: [Float]) -> [Float] {
    let mean = values.reduce(0, +) / Float(values.count)
    let centered = values.map { $0 - mean }
    let length = centered.reduce(0) { $0 + $1 * $1 }.squareRoot()
    return length > 0 ? centered.map { $0 / length } : centered
}
