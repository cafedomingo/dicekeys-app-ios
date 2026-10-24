//
//  Slots.swift
//  ReadDiceKey
//
//  The lines in each of the grid's 25 slots: every line read goes to the slot its face is in,
//  and each slot's missing lines are then read where the grid says their bars are.
//

import DiceKeySpecification
import simd

/// The lines read at one position of the grid.
struct Slot: Sendable {
    var underline: Undoverline?
    var overline: Undoverline?
    /// The face its printed text settled, when its lines do not name one together.
    var faceFromText: FaceWithUnderlineAndOverlineCode?

    /// The middle of the face.
    var center: Point? {
        switch (underline, overline) {
        case (let underline?, let overline?): (underline.center + overline.center) / 2
        case (let line?, nil), (nil, let line?): line.faceCenter
        case (nil, nil): nil
        }
    }

    /// The direction the face reads in, in radians.
    var angle: Float? {
        switch (underline, overline) {
        // The overline is a quarter turn counterclockwise of the reading direction from the underline.
        case (let underline?, let overline?): (overline.center - underline.center).angle + .pi / 2
        case (let line?, nil), (nil, let line?): line.direction.angle
        case (nil, nil): nil
        }
    }

    /// The length of the face's edge in pixels.
    var size: Float? {
        let lengths = [underline?.length, overline?.length].compactMap { $0 }
        return lengths.isEmpty ? nil : lengths.reduce(0, +) / Float(lengths.count)
    }

    /// The face, when its two lines name the same one or its text settled it.
    var face: FaceWithUnderlineAndOverlineCode? {
        if let fromUnderline = underline?.bits.face, let fromOverline = overline?.bits.face,
            fromUnderline.underlineCode == fromOverline.underlineCode
        {
            return fromUnderline
        }
        return faceFromText
    }
}

/// The 25 slots of `grid`, rows top to bottom, each holding the underline and the overline whose
/// faces are in it.
///
/// Of two lines of a kind whose faces are in one slot, the one nearer its middle is kept. Then
/// each slot missing a line is read where the line must be, which recovers lines too faint or
/// broken up to be found as rectangles, or too near or far for their size to pass as one: a
/// line it holds says where its face's other line is, and in a slot holding neither the bars
/// are tried on all four sides of its middle. Both are placed on the grid, where every face is
/// the same square however perspective shows it, its side the median length of the lines on
/// the grid. A line read this way fills its kind if the slot still lacks it and its face is in
/// that slot.
func readSlots(_ lines: [Undoverline], on grid: Grid, in image: GrayImage) -> [Slot] {
    var slots = [Slot](repeating: Slot(), count: 25)
    for line in lines {
        guard let index = grid.slot(of: line.faceCenter) else { continue }
        let center = grid.center(of: index)
        if slots[index][keyPath: line.kind].map({
            simd_distance($0.faceCenter, center) > simd_distance(line.faceCenter, center)
        }) ?? true {
            slots[index][keyPath: line.kind] = line
        }
    }

    let faceSide = median(lines.map { simd_distance(grid.position(of: $0.start), grid.position(of: $0.end)) })
    let toLine = faceSide * Float(FaceDimensionsFractional.centerOfUndoverlineToCenterOfFace)
    for index in slots.indices {
        let held = [slots[index].underline, slots[index].overline].compactMap { $0 }
        var bars = held.map { grid.oppositeBar(of: $0) }
        if held.isEmpty {
            let middle = columnAndRow(of: index)
            for (along, toward) in [(SIMD2<Float>(1, 0), SIMD2<Float>(0, 1)), (SIMD2(0, 1), SIMD2(1, 0))] {
                for side: Float in [1, -1] {
                    let center = middle + toward * (side * toLine)
                    bars.append(grid.bar(from: center - along * (faceSide / 2), to: center + along * (faceSide / 2)))
                }
            }
        }
        for bar in bars {
            guard slots[index].underline == nil || slots[index].overline == nil,
                let line = readUndoverline(in: image, bar: bar), grid.slot(of: line.faceCenter) == index,
                slots[index][keyPath: line.kind] == nil
            else { continue }
            slots[index][keyPath: line.kind] = line
        }
    }
    return slots
}

extension Undoverline {
    /// Where a slot holds a line of this one's kind.
    fileprivate var kind: WritableKeyPath<Slot, Undoverline?> {
        bits.isOverline ? \.overline : \.underline
    }
}

extension Grid {
    /// The bar from `start` to `end`, fractional columns and rows, as it lies in the frame.
    fileprivate func bar(from start: SIMD2<Float>, to end: SIMD2<Float>) -> Bar {
        let (from, to) = (point(at: start), point(at: end))
        let length = simd_distance(from, to)
        return Bar(
            center: (from + to) / 2, axis: (to - from) / length, length: length,
            width: length * Float(FaceDimensionsFractional.undoverlineThickness))
    }

    /// Where the other line of `line`'s face is: across the face from it, as the face lies on the grid.
    fileprivate func oppositeBar(of line: Undoverline) -> Bar {
        let (start, end) = (position(of: line.start), position(of: line.end))
        let towardFace = (end - start).turnedClockwise * (line.bits.isOverline ? 1 : -1)
        let toOpposite = towardFace * (2 * Float(FaceDimensionsFractional.centerOfUndoverlineToCenterOfFace))
        return bar(from: start + toOpposite, to: end + toOpposite)
    }
}
