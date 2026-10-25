//
//  Slots.swift
//  ReadDiceKey
//
//  The lines in each of the grid's slots: every line read goes to the slot its face is in,
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
    /// Whether a line was read only where the grid puts it, because no bar was found for it.
    /// Whatever kept the bar from being found, such as a finger or the frame's edge over its digit
    /// end, can make it name the face of the line beside it, and where there is no bar, noise can
    /// decode a face by chance, so it is not a second vote on its own.
    var hasLineReadAtGrid = false

    /// The middle of the face.
    var center: Point? {
        switch (underline, overline) {
        case (let underline?, let overline?): (underline.center + overline.center) / 2
        case (let line?, nil), (nil, let line?): line.faceCenter
        case (nil, nil): nil
        }
    }

    /// The direction the face reads in, in radians: a quarter turn clockwise of the way from its
    /// underline to its overline.
    var angle: Float? {
        switch (underline, overline) {
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

    /// The face, when its two lines name the same one and neither was read only at the grid, or
    /// when its text settled it.
    var face: FaceWithUnderlineAndOverlineCode? {
        if !hasLineReadAtGrid, let fromUnderline = underline?.bits.face, let fromOverline = overline?.bits.face,
            fromUnderline.underlineCode == fromOverline.underlineCode
        {
            return fromUnderline
        }
        return faceFromText
    }
}

/// The slots of `grid`, rows top to bottom, each holding the underline and the overline whose
/// faces are in it.
///
/// A line shorter on the grid than `Tuning.Slots.minimumLineLength` of the median is left out,
/// since a bar cut short drops its last dots and a die's two bars cut alike agree on a wrong
/// face. Of two lines of a kind whose faces are in one slot, the one nearer its middle is kept.
/// Then each slot missing a line is read where the line must be, which recovers lines too faint
/// or broken up to be found as rectangles, or too near or far for their size to pass as one. The
/// bars are placed in columns and rows, where every face is the same square however
/// perspective shows it, and one is read only if both its ends are in the frame. A line read
/// there fills its kind only if its face is in that slot.
func readSlots(_ lines: [Undoverline], on grid: Grid, in image: GrayImage) -> [Slot] {
    var slots = [Slot](repeating: Slot(), count: Grid.slotCount)
    let faceSide = median(lines.map(grid.faceSide(of:)))
    for line in lines where grid.faceSide(of: line) >= Tuning.Slots.minimumLineLength * faceSide {
        guard let index = grid.slot(of: line.faceCenter) else { continue }
        let center = grid.center(of: index)
        if slots[index][keyPath: line.kind].map({
            simd_distance($0.faceCenter, center) > simd_distance(line.faceCenter, center)
        }) ?? true {
            slots[index][keyPath: line.kind] = line
        }
    }

    for index in slots.indices {
        let held = [slots[index].underline, slots[index].overline].compactMap { $0 }
        let bars = held.isEmpty ? grid.bars(around: index, faceSide: faceSide) : held.map(grid.oppositeBar(of:))
        for bar in bars where slots[index].underline == nil || slots[index].overline == nil {
            guard image.containsEnds(of: bar), let line = readUndoverline(in: image, bar: bar),
                grid.slot(of: line.faceCenter) == index,
                slots[index][keyPath: line.kind] == nil
            else { continue }
            slots[index][keyPath: line.kind] = line
            slots[index].hasLineReadAtGrid = true
        }
    }
    return slots
}

extension GrayImage {
    /// Whether both ends of `bar` lie inside the image. Off the image a dot samples as dark, so
    /// a bar the frame's edge cuts can read as another code.
    fileprivate func containsEnds(of bar: Bar) -> Bool {
        [-bar.length / 2, bar.length / 2].allSatisfy { along in
            let end = bar.center + bar.axis * along
            return end.x >= 0 && end.y >= 0 && end.x < Float(width) && end.y < Float(height)
        }
    }
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

    /// Where the bars of a face `faceSide` columns across in slot `slot` may be, on all four sides
    /// of its middle: below and above it lying along its row, then right and left of it lying
    /// along its column.
    fileprivate func bars(around slot: Int, faceSide: Float) -> [Bar] {
        let middle = columnAndRow(of: slot)
        let toLine = faceSide * Float(FaceDimensionsFractional.centerOfUndoverlineToCenterOfFace)
        let sides: [(along: SIMD2<Float>, toward: SIMD2<Float>)] = [
            ([1, 0], [0, 1]), ([1, 0], [0, -1]), ([0, 1], [1, 0]), ([0, 1], [-1, 0])
        ]
        return sides.map { along, toward in
            let center = middle + toward * toLine
            return bar(from: center - along * (faceSide / 2), to: center + along * (faceSide / 2))
        }
    }
}
