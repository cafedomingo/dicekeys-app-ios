//
//  Grid.swift
//  ReadDiceKey
//
//  From undoverlines to the 5x5 grid of dice: pairing each underline with its overline,
//  fitting the grid, and placing every line in it.
//

import DiceKeySpecification
import simd

/// The lines read at one position of the grid.
struct Slot: Sendable {
    var underline: Undoverline?
    var overline: Undoverline?

    /// The middle of the face.
    var center: Point? {
        switch (underline, overline) {
        case let (underline?, overline?): (underline.center + overline.center) / 2
        case let (line?, nil), let (nil, line?): line.faceCenter
        case (nil, nil): nil
        }
    }

    /// The direction the face reads in, in radians.
    var angle: Float? {
        switch (underline, overline) {
        // The overline is a quarter turn anticlockwise of the reading direction from the underline.
        case let (underline?, overline?): (overline.center - underline.center).angle + .pi / 2
        case let (line?, nil), let (nil, line?): line.direction.angle
        case (nil, nil): nil
        }
    }

    /// The length of the face's edge in pixels.
    var size: Float? {
        let lengths = [underline?.length, overline?.length].compactMap { $0 }
        return lengths.isEmpty ? nil : lengths.reduce(0, +) / Float(lengths.count)
    }

    /// The face, when its two lines name the same one.
    var face: FaceWithUnderlineAndOverlineCode? {
        guard let fromUnderline = underline?.bits.face, let fromOverline = overline?.bits.face,
              fromUnderline.letter == fromOverline.letter, fromUnderline.digit == fromOverline.digit else { return nil }
        return fromUnderline
    }
}

/// The 5x5 grid as it lies in the frame.
struct Grid: Sendable {
    let center: Point
    /// From one column to the next.
    let across: Point
    /// From one row to the next.
    let down: Point

    /// The index (row * 5 + column) of the position within a quarter step of `point`.
    func slot(of point: Point) -> Int? {
        let offset = point - center
        let determinant = crossProduct(across, down)
        guard determinant != 0 else { return nil }
        let column = crossProduct(offset, down) / determinant + 2
        let row = crossProduct(across, offset) / determinant + 2
        let nearestColumn = column.rounded(), nearestRow = row.rounded()
        guard abs(column - nearestColumn) <= 0.25, abs(row - nearestRow) <= 0.25,
              (0...4).contains(nearestColumn), (0...4).contains(nearestRow) else { return nil }
        return Int(nearestRow) * 5 + Int(nearestColumn)
    }
}

/// Reads the undoverlines in the image and places them in the grid; nil when no grid is found.
func readSlots(in image: GrayImage) -> (slots: [Slot], grid: Grid)? {
    let lines = findBars(in: image).compactMap { readUndoverline(in: image, bar: $0) }
    guard !lines.isEmpty else { return nil }
    let faceSize = median(lines.map(\.length))

    // Pair each underline with the overline that sits where it says the overline should and
    // says the same of the underline: the two misses together within a quarter of a face.
    var overlines = lines.filter(\.bits.isOverline)
    var faces: [Slot] = []
    var strays: [Undoverline] = []
    for underline in lines where !underline.bits.isOverline {
        let misfit = overlines.map {
            simd_distance(underline.center, $0.oppositeBar.center) + simd_distance($0.center, underline.oppositeBar.center)
        }
        if let best = misfit.indices.min(by: { misfit[$0] < misfit[$1] }), misfit[best] <= faceSize / 4 {
            faces.append(Slot(underline: underline, overline: overlines.remove(at: best)))
        } else {
            strays.append(underline)
        }
    }
    strays += overlines

    guard let grid = fitGrid(to: faces, faceSize: faceSize) else { return nil }
    var slots = [Slot](repeating: Slot(), count: 25)
    for face in faces {
        if let center = face.center, let index = grid.slot(of: center) {
            slots[index] = face
        }
    }
    // A line whose partner was not found says where its partner should be; read it there.
    for line in strays {
        guard let index = grid.slot(of: line.faceCenter) else { continue }
        let partner = { readUndoverline(in: image, bar: line.oppositeBar).flatMap { $0.bits.isOverline != line.bits.isOverline ? $0 : nil } }
        if line.bits.isOverline, slots[index].overline == nil {
            slots[index].overline = line
            if slots[index].underline == nil { slots[index].underline = partner() }
        } else if !line.bits.isOverline, slots[index].underline == nil {
            slots[index].underline = line
            if slots[index].overline == nil { slots[index].overline = partner() }
        }
    }
    return (slots, grid)
}

/// The grid through a face that has at least four others in line with it along its row and
/// along its column (within a face's width), evenly spaced both ways.
private func fitGrid(to faces: [Slot], faceSize: Float) -> Grid? {
    let centers = faces.compactMap(\.center)
    for face in faces {
        guard let origin = face.center, let angle = face.angle else { continue }
        // A row runs along or across the reading direction; take whichever is within 45
        // degrees of the image's x axis, so rows run left to right and columns top to bottom.
        let rowAngle = angle - (angle / (.pi / 2)).rounded() * (.pi / 2)
        let alongRow = Point(angle: rowAngle), alongColumn = alongRow.turnedClockwise
        let row = centers.filter { abs(crossProduct($0 - origin, alongRow)) <= faceSize }
            .sorted { simd_dot($0 - origin, alongRow) < simd_dot($1 - origin, alongRow) }
        let column = centers.filter { abs(crossProduct($0 - origin, alongColumn)) <= faceSize }
            .sorted { simd_dot($0 - origin, alongColumn) < simd_dot($1 - origin, alongColumn) }
        guard row.count >= 5, column.count >= 5,
              let across = evenStep(row), let down = evenStep(column),
              let columnIndex = row.firstIndex(of: origin), let rowIndex = column.firstIndex(of: origin) else { continue }
        return Grid(center: origin + across * Float(2 - columnIndex) + down * Float(2 - rowIndex), across: across, down: down)
    }
    return nil
}

/// The mean step between consecutive points, if every step is within 25% of it.
private func evenStep(_ points: [Point]) -> Point? {
    guard let first = points.first, let last = points.last, points.count > 1 else { return nil }
    let mean = (last - first) / Float(points.count - 1)
    for (a, b) in zip(points, points.dropFirst()) where simd_distance(b - a, mean) > 0.25 * mean.length {
        return nil
    }
    return mean
}

/// The z component of the cross product: positive when `b` is clockwise of `a` on screen.
private func crossProduct(_ a: Point, _ b: Point) -> Float {
    a.x * b.y - a.y * b.x
}

private func median(_ values: [Float]) -> Float {
    let sorted = values.sorted()
    let middle = sorted.count / 2
    return sorted.count % 2 == 1 ? sorted[middle] : (sorted[middle - 1] + sorted[middle]) / 2
}
