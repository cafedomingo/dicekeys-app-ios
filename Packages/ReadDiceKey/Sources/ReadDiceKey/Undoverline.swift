//
//  Undoverline.swift
//  ReadDiceKey
//
//  Reading one bar: finding the line through its middle, sampling its 11 dots, and decoding
//  them into the face they name and the direction the face is turned, when they split
//  cleanly into dark and light.
//

import DiceKeySpecification
import simd

/// An underline or overline read from the image.
struct Undoverline: Sendable {
    /// The letter end of the line.
    let start: Point
    /// The digit end of the line.
    let end: Point
    let bits: UndoverlineBits

    var center: Point { (start + end) / 2 }
    var length: Float { simd_distance(start, end) }
    /// The direction the face reads in, from its letter to its digit.
    var direction: Point { simd_normalize(end - start) }

    /// From the middle of this line to the middle of its face.
    private var towardFaceCenter: Point {
        let towardFace = bits.isOverline ? direction.turnedClockwise : -direction.turnedClockwise
        return towardFace * (length * Float(FaceDimensionsFractional.centerOfUndoverlineToCenterOfFace))
    }

    /// Where the middle of this line's face is.
    var faceCenter: Point { center + towardFaceCenter }
}

/// An undoverline's 11 bits, taken from its letter end, are a 1, the overline flag, the
/// 8-bit code and a 0. Read from the other end the 1 comes last, which is how the direction
/// of the line (and so the rotation of the face) is known.
struct UndoverlineBits {
    let isOverline: Bool
    let code: UInt8
    /// True when the bits were read from the digit end.
    let wasReversed: Bool

    /// Decodes bits sampled first-dot-first (the first dot is the most significant bit);
    /// nil unless exactly one end is a 1.
    init?(_ bits: UInt32) {
        let lastDot = dotCenters.count - 1
        let first = (bits >> lastDot) & 1
        let last = bits & 1
        guard first != last else { return nil }
        wasReversed = last == 1
        var forward = bits
        if wasReversed {
            forward = 0
            for dot in 0...lastDot where (bits >> dot) & 1 == 1 {
                forward |= 1 << (lastDot - dot)
            }
        }
        isOverline = (forward >> (lastDot - 1)) & 1 == 1
        code = UInt8(truncatingIfNeeded: forward >> 1)
    }

    /// The face this line names, if any.
    var face: FaceWithUnderlineAndOverlineCode? {
        isOverline
            ? overlineCodeToFaceWithUnderlineAndOverlineCode[Int(code)]
            : underlineCodeToFaceWithUnderlineAndOverlineCode[Int(code)]
    }
}

/// Where each of the 11 dots sits along an undoverline, as a fraction of its length from the
/// letter end.
private let dotCenters = FaceDimensionsFractional.dotCentersAsFractionOfUndoverline.map { Float($0) }

/// Reads the bar in `bar` as an undoverline, or nil when its dots are not the code of a face.
///
/// The rectangle can take in a little of whatever the bar touches at the brightness it was
/// found at, or miss a blurred end, so each end of the line is put where the brightness drops
/// most steeply into the bar, within `Tuning.Lines.endSearch` of the rectangle's end. A fixed
/// brightness would not do: a sheen on the ink or a shadow on the die beyond the bar moves
/// where it is crossed. Each dot is the median of the pixels around its center, and dark and
/// light are split where the samples fall into two tightest groups, with a clear gap between
/// them.
func readUndoverline(in image: GrayImage, bar: Bar) -> Undoverline? {
    guard bar.length >= 1, bar.center.x.isFinite, bar.center.y.isFinite else { return nil }
    let halfLength = bar.axis * (bar.length / 2)
    let start = image.barEnd(near: bar.center - halfLength, outward: -bar.axis, barLength: bar.length)
    let end = image.barEnd(near: bar.center + halfLength, outward: bar.axis, barLength: bar.length)
    let dots = image.samples(from: start, to: end, at: dotCenters)
    let dotThreshold = twoLevelThreshold(dots)
    let bits = dots.reduce(UInt32(0)) { ($0 << 1) | ($1 > dotThreshold ? 1 : 0) }
    guard let decoded = UndoverlineBits(bits), decoded.face != nil, splitsCleanly(dots, at: dotThreshold) else {
        return nil
    }
    return decoded.wasReversed
        ? Undoverline(start: end, end: start, bits: decoded)
        : Undoverline(start: start, end: end, bits: decoded)
}

/// Whether the gap between the dots darker and lighter than `threshold` is at least
/// `Tuning.Lines.minimumDotGap` of the distance between their means. Decoded dots have at least
/// one of each.
private func splitsCleanly(_ dots: [UInt8], at threshold: UInt8) -> Bool {
    let dark = dots.filter { $0 <= threshold }.map(Float.init)
    let light = dots.filter { $0 > threshold }.map(Float.init)
    let mean = { (values: [Float]) in values.reduce(0, +) / Float(values.count) }
    return light.min()! - dark.max()! >= Tuning.Lines.minimumDotGap * (mean(light) - mean(dark))
}

/// The brightness that splits `samples` into a dark and a light group with the least total
/// squared distance from each group's mean, with at least four samples in each group, as
/// every code has at least four dark and four light dots. It lies halfway between the
/// lightest dark and the darkest light sample.
func twoLevelThreshold(_ samples: [UInt8]) -> UInt8 {
    let sorted = samples.sorted()
    let firstSplit = MinNumberOfBlackDotsInUndoverline
    let lastSplit = sorted.count - MinNumberOfWhiteDotsInUndoverline
    precondition(firstSplit <= lastSplit, "too few samples to split")
    var sums = [Double](repeating: 0, count: sorted.count + 1)
    var squares = [Double](repeating: 0, count: sorted.count + 1)
    for (i, value) in sorted.enumerated() {
        sums[i + 1] = sums[i] + Double(value)
        squares[i + 1] = squares[i] + Double(value) * Double(value)
    }
    func spread(_ from: Int, _ to: Int) -> Double {
        let sum = sums[to] - sums[from]
        return squares[to] - squares[from] - sum * sum / Double(to - from)
    }
    var best = (spread: Double.infinity, split: firstSplit)
    for split in firstSplit...lastSplit {
        let total = spread(0, split) + spread(split, sorted.count)
        if total < best.spread {
            best = (total, split)
        }
    }
    return UInt8((Int(sorted[best.split - 1]) + Int(sorted[best.split])) / 2)
}

// MARK: - Sampling

extension GrayImage {
    /// The point within `Tuning.Lines.endSearch` of `barLength` either side of `point`, along
    /// `outward`, where the brightness drops most steeply going inward. It steps one pixel at a
    /// time along whichever axis `outward` runs closer to.
    func barEnd(near point: Point, outward: Point, barLength: Float) -> Point {
        let step = outward / max(abs(outward.x), abs(outward.y))
        let acrossIsVertical = abs(outward.x) > abs(outward.y)
        let reach = Int((barLength * Tuning.Lines.endSearch / step.length).rounded(.up))
        let pixels = Tuning.Lines.endSamplePixels
        var steepest = (drop: Int.min, point: point)
        for offset in -reach...reach {
            let candidate = point + step * Float(offset)
            let drop =
                Int(sample(at: candidate + step, pixels: pixels, acrossIsVertical: acrossIsVertical))
                - Int(sample(at: candidate - step, pixels: pixels, acrossIsVertical: acrossIsVertical))
            if drop > steepest.drop {
                steepest = (drop, candidate)
            }
        }
        return steepest.point
    }

    /// Samples at fractions of the way from `start` to `end`, each the median of a
    /// neighborhood sized to the spacing between samples.
    func samples(from start: Point, to end: Point, at fractions: [Float]) -> [UInt8] {
        let delta = end - start
        let spacing = delta.length / Float(fractions.count)
        let pixels =
            Tuning.Lines.samplePixels.first { spacing < $0.spacingUnder }?.pixels ?? horizontalFirstOffsets.count
        let acrossIsVertical = abs(delta.x) > abs(delta.y)
        return fractions.map { sample(at: start + delta * $0, pixels: pixels, acrossIsVertical: acrossIsVertical) }
    }

    /// The median of the `pixels` nearest `point` that fall inside the image, or 0 if none do.
    /// After `point` itself come the two either side of it across the line (`acrossIsVertical`
    /// for a line that runs more horizontally than vertically), so 3 lie in a line across it.
    func sample(at point: Point, pixels: Int, acrossIsVertical: Bool) -> UInt8 {
        let x = Int(point.x.rounded())
        let y = Int(point.y.rounded())
        let offsets = acrossIsVertical ? verticalFirstOffsets : horizontalFirstOffsets
        return withUnsafeTemporaryAllocation(of: UInt8.self, capacity: offsets.count) { values in
            var count = 0
            for (dx, dy) in offsets.prefix(pixels) {
                let sx = x + dx
                let sy = y + dy
                guard sx >= 0, sy >= 0, sx < width, sy < height else { continue }
                values[count] = self.pixels[sy * width + sx]
                count += 1
            }
            guard count > 0 else { return 0 }
            var taken = UnsafeMutableBufferPointer(rebasing: values[0..<count])
            taken.sort()
            return count % 2 == 1
                ? taken[count / 2]
                : UInt8((Int(taken[count / 2 - 1]) + Int(taken[count / 2])) / 2)
        }
    }
}

/// The pixels around a sample, nearest first, the two beside it before the two above and below.
private let horizontalFirstOffsets: [(Int, Int)] = [
    (0, 0),
    (1, 0), (-1, 0), (0, 1), (0, -1),
    (1, 1), (-1, -1), (1, -1), (-1, 1),
    (2, 0), (-2, 0), (0, 2), (0, -2),
    (2, -1), (-2, -1), (-1, 2), (-1, -2),
    (2, 1), (-2, 1), (1, 2), (1, -2)
]

/// The same pixels, mirrored across the diagonal: the two above and below before the two beside.
private let verticalFirstOffsets = horizontalFirstOffsets.map { ($1, $0) }
