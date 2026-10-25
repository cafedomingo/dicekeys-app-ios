//
//  GridFit.swift
//  ReadDiceKey
//
//  Fitting the grid to the lines read: the step between dice and the direction of the rows,
//  the placing that puts the most faces on whole columns and rows, refits flat and then in
//  perspective, and pinning it to the key's 5x5 slots once the dice beyond it are dropped.
//

import simd

/// A line's face center, at a whole column and row of the grid.
private typealias Member = (point: Point, position: SIMD2<Int>)

/// The grid of the key the lines are on, its slots the key's dice; nil when the lines do not
/// make one.
///
/// Rows run in the direction the lines share, their angles taken four times over so that a
/// face's four turns count as one, and within 45 degrees of the frame's x axis, so row 0 is the
/// top of the key as the camera sees it. The perspective refits gather only lines near those
/// the flat grid kept, so dice farther out are not taken in. The grid is pinned to the key when
/// the lines left lie in each of five columns and five rows side by side and in no others, make
/// up most of the lines, fill more than one slot of each outermost row and column, and none of
/// the lines in its slots measures, in columns and rows, more than
/// `Tuning.Grid.maximumFaceSideDeviation` off their median, since every face is the same square
/// on the grid: dice scattered or lying beside the key rarely pass all four, and a grid
/// stretched across a steep tilt, which measures the faces at one end of the key far larger than
/// at the other, fails the last.
func fitGrid(to lines: [Undoverline]) -> Grid? {
    guard lines.count >= Tuning.Grid.minimumLines else { return nil }
    let centers = lines.map(\.faceCenter)
    let faceSize = median(lines.map(\.length))
    let neighbors = centers.compactMap { center in
        centers.map { simd_distance($0, center) }.filter { $0 > Tuning.Grid.sameDieDistance * faceSize }.min()
    }
    guard neighbors.count >= Tuning.Grid.minimumLines else { return nil }
    let step = median(neighbors)
    guard step >= faceSize else { return nil }
    let rowAngle = lines.reduce(Point.zero) { $0 + Point(angle: 4 * $1.direction.angle) }.angle / 4
    let across = Point(angle: rowAngle) * step

    func members(of grid: Grid) -> [Member] {
        centers.compactMap { center in grid.nearestPosition(to: center).map { (center, $0) } }
    }
    let anchors = centers.map { Grid(origin: $0, across: across, down: across.turnedClockwise) }
    let counts = anchors.map { members(of: $0).count }
    var grid = anchors[counts.indices.max { counts[$0] < counts[$1] }!]
    for _ in 0..<Tuning.Grid.refits {
        guard let refit = grid.refitted(to: members(of: grid), perspective: false) else { return nil }
        grid = refit
    }

    var onKey = withoutStrays(members(of: grid))
    if onKey.count >= Tuning.Grid.minimumLinesForPerspective {
        let (low, high) = extent(of: onKey)
        let window = Tuning.Grid.perspectiveWindow
        for _ in 0..<Tuning.Grid.refits {
            guard let refit = grid.refitted(to: onKey, perspective: true) else { break }
            grid = refit
            onKey = members(of: grid).filter { all($0.position .>= low &- window .& $0.position .<= high &+ window) }
        }
    }
    onKey = withoutStrays(onKey)

    guard onKey.count >= Tuning.Grid.minimumLines,
        Float(onKey.count) >= Tuning.Grid.minimumShareOnKey * Float(lines.count)
    else { return nil }
    let (low, high) = extent(of: onKey)
    let slots = Set(onKey.map(\.position))
    guard
        (0..<2).allSatisfy({ axis in
            Set(slots.map { $0[axis] }) == Set(low[axis]..<low[axis] + Grid.slotsPerSide)
        }),
        [low, high].allSatisfy({ edge in
            (0..<2).allSatisfy { axis in
                slots.count(where: { $0[axis] == edge[axis] }) >= Tuning.Grid.minimumSlotsOnEachEdge
            }
        })
    else { return nil }
    let pinned = grid.shifted(by: low)
    let sides = lines.filter { pinned.slot(of: $0.faceCenter) != nil }.map(pinned.faceSide(of:))
    let middle = median(sides)
    guard sides.allSatisfy({ abs($0 - middle) <= Tuning.Grid.maximumFaceSideDeviation * middle }) else { return nil }
    return pinned
}

/// The members less the outermost columns, then rows, that hold too few lines to be part of the
/// key, while they span more than the key. Of the two ends, the one with fewer lines goes, the
/// lower on a tie, if it holds no more than `Tuning.Grid.maximumStrayLines`; with one column or
/// row too many, only if the other end fills at least `Tuning.Grid.minimumSlotsOppositeStrays`
/// slots, since a sparse outer column of the key beside two stray dice would otherwise go in
/// their place. Once an end stays, the rest do.
private func withoutStrays(_ members: [Member]) -> [Member] {
    var members = members
    for axis in 0..<2 {
        while let span = span(of: members, along: axis), span.count > Grid.slotsPerSide {
            let lowEnd = members.filter { $0.position[axis] == span.lowerBound }
            let highEnd = members.filter { $0.position[axis] == span.upperBound }
            let (cut, other) = lowEnd.count <= highEnd.count ? (span.lowerBound, highEnd) : (span.upperBound, lowEnd)
            guard min(lowEnd.count, highEnd.count) <= Tuning.Grid.maximumStrayLines,
                span.count > Grid.slotsPerSide + 1
                    || Set(other.map(\.position)).count >= Tuning.Grid.minimumSlotsOppositeStrays
            else { break }
            members.removeAll { $0.position[axis] == cut }
        }
    }
    return members
}

/// The columns (`axis` 0) or rows (1) the members lie in, nil when there are none.
private func span(of members: [Member], along axis: Int) -> ClosedRange<Int>? {
    let positions = members.map { $0.position[axis] }
    guard let low = positions.min(), let high = positions.max() else { return nil }
    return low...high
}

/// The lowest and the highest column and row of the members, of which there is at least one.
private func extent(of members: [Member]) -> (low: SIMD2<Int>, high: SIMD2<Int>) {
    let positions = members.map(\.position)
    return (positions.reduce(positions[0], pointwiseMin), positions.reduce(positions[0], pointwiseMax))
}
