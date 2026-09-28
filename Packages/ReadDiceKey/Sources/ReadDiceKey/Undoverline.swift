//
//  Undoverline.swift
//  ReadDiceKey
//
//  Reading one bar: finding the line through its middle, sampling its 11 dots, and decoding
//  them into the face they name and the direction the face is turned.
//

import DiceKeySpecification
import simd

/// An underline or overline read from the image.
struct Undoverline: Sendable {
    /// The rectangle the line was found in.
    let bar: Bar
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

    /// Where the face's other line should be.
    var oppositeBar: Bar {
        Bar(center: bar.center + 2 * towardFaceCenter, axis: bar.axis, length: bar.length, width: bar.width)
    }
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
        let first = (bits >> 10) & 1, last = bits & 1
        guard first != last else { return nil }
        wasReversed = last == 1
        var forward = bits
        if wasReversed {
            forward = 0
            for position in 0..<11 where (bits >> position) & 1 == 1 {
                forward |= 1 << (10 - position)
            }
        }
        isOverline = (forward >> 9) & 1 == 1
        code = UInt8(truncatingIfNeeded: forward >> 1)
    }

    /// The face this line names, if any.
    var face: FaceWithUnderlineAndOverlineCode? {
        isOverline ? overlineCodeToFaceWithUnderlineAndOverlineCode[Int(code)] : underlineCodeToFaceWithUnderlineAndOverlineCode[Int(code)]
    }
}

/// Where each of the 11 dots sits along an undoverline, as a fraction of its length from the
/// letter end.
private let dotCenters = FaceDimensionsFractional.dotCentersAsFractionOfUndoverline.map { Float($0) }

/// Where the outline of a bar is sampled along its length to find how dark the bar is.
private let outlinePositions = (0...30).map { Float($0) / 30 }

/// Reads the bar in `bar` as an undoverline, or nil when its dots are not a valid code.
///
/// The rectangle can take in a little of whatever the bar touches at the brightness it was
/// found at, so the line through its middle is first stretched 3% each way and then pulled
/// back to the first dark pixel at each end. Each dot is the median of the pixels around its
/// center, and dark and light are split where the samples fall into two tightest groups.
func readUndoverline(in image: GrayImage, bar: Bar) -> Undoverline? {
    guard bar.length >= 1, bar.center.x.isFinite, bar.center.y.isFinite else { return nil }
    var start = bar.center - bar.axis * (bar.length / 2)
    var end = bar.center + bar.axis * (bar.length / 2)
    let darkBelow = twoLevelThreshold(image.samples(from: start, to: end, at: outlinePositions))

    let stretch = (end - start) * 0.03
    start -= stretch
    end += stretch
    let delta = end - start
    let step = delta / max(abs(delta.x), abs(delta.y))
    let acrossIsVertical = abs(delta.x) > abs(delta.y)
    let (outerStart, outerEnd) = (start, end)
    while image.sample(at: start, pixels: 3, acrossIsVertical: acrossIsVertical) > darkBelow,
          isPoint(start + step, between: outerStart, and: outerEnd) {
        start += step
    }
    while image.sample(at: end, pixels: 3, acrossIsVertical: acrossIsVertical) > darkBelow,
          isPoint(end - step, between: start, and: outerEnd) {
        end -= step
    }

    let dots = image.samples(from: start, to: end, at: dotCenters)
    let dotThreshold = twoLevelThreshold(dots)
    let bits = dots.reduce(UInt32(0)) { ($0 << 1) | ($1 > dotThreshold ? 1 : 0) }
    guard let decoded = UndoverlineBits(bits) else { return nil }
    return decoded.wasReversed
        ? Undoverline(bar: bar, start: end, end: start, bits: decoded)
        : Undoverline(bar: bar, start: start, end: end, bits: decoded)
}

/// Whether `point` lies in the axis-aligned box spanned by `a` and `b`.
private func isPoint(_ point: Point, between a: Point, and b: Point) -> Bool {
    all(point .>= simd_min(a, b)) && all(point .<= simd_max(a, b))
}

/// The brightness that splits `samples` into a dark and a light group with the least total
/// squared distance from each group's mean, with at least four samples in each group, as
/// every code has at least four dark and four light dots. It lies halfway between the
/// lightest dark and the darkest light sample.
func twoLevelThreshold(_ samples: [UInt8]) -> UInt8 {
    let sorted = samples.sorted()
    let firstSplit = MinNumberOfBlackDotsInUndoverline, lastSplit = sorted.count - MinNumberOfWhiteDotsInUndoverline
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
    /// Samples at fractions of the way from `start` to `end`, each the median of a
    /// neighborhood sized to the spacing between samples.
    func samples(from start: Point, to end: Point, at fractions: [Float]) -> [UInt8] {
        let delta = end - start
        let pixels = pixelsPerSample(forSpacing: delta.length / Float(fractions.count))
        let acrossIsVertical = abs(delta.x) > abs(delta.y)
        return fractions.map { sample(at: start + delta * $0, pixels: pixels, acrossIsVertical: acrossIsVertical) }
    }

    /// The median of the `pixels` nearest `point` that fall inside the image, or 0 if none do.
    /// Three pixels are taken across the line (`acrossIsVertical` for a line that runs
    /// more horizontally than vertically), so the sample stays inside a thin bar.
    func sample(at point: Point, pixels: Int, acrossIsVertical: Bool) -> UInt8 {
        let x = Int(point.x.rounded()), y = Int(point.y.rounded())
        let offsets = pixels == 3 && acrossIsVertical ? verticalFirstOffsets : horizontalFirstOffsets
        return withUnsafeTemporaryAllocation(of: UInt8.self, capacity: offsets.count) { values in
            var count = 0
            for (dx, dy) in offsets.prefix(pixels) {
                let sx = x + dx, sy = y + dy
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

/// How many pixels make up one sample when samples are `spacing` pixels apart.
private func pixelsPerSample(forSpacing spacing: Float) -> Int {
    switch spacing {
    case ..<2: 1
    case ..<3: 3
    case ..<4: 5
    case ..<5: 9
    case ..<5.5: 13
    default: 21
    }
}

/// The pixels around a sample, nearest first.
private let horizontalFirstOffsets: [(Int, Int)] = [
    (0, 0),
    (1, 0), (-1, 0), (0, 1), (0, -1),
    (1, 1), (-1, -1), (1, -1), (-1, 1),
    (2, 0), (-2, 0), (0, 2), (0, -2),
    (2, -1), (-2, -1), (-1, 2), (-1, -2),
    (2, 1), (-2, 1), (1, 2), (1, -2)
]

private let verticalFirstOffsets: [(Int, Int)] = [(0, 0), (0, 1), (0, -1)]
