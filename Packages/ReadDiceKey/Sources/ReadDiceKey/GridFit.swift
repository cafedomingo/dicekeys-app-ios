//
//  GridFit.swift
//  ReadDiceKey
//
//  Fitting the grid to the lines read: the step between dice and the direction of the rows,
//  the placing that puts the most faces on whole columns and rows, refits flat and then in
//  perspective, and pinning it to the key's 5x5 slots once the dice beyond it are dropped.
//

import simd

/// Face centers closer than this many faces are one die's two lines.
private let sameDieDistance: Float = 0.8
/// Times the grid is refitted to the lines it gathers.
private let refits = 3
/// Fewest lines a grid is fitted to or pinned with.
private let minimumLinesOnGrid = 8
/// Fewest lines on the flat grid before perspective is fitted.
private let minimumLinesForPerspective = 16
/// An outermost column or row with no more lines than this is strays beyond the key.
private let maximumStrayLines = 2
/// The least share of all decoded lines that must lie on the key.
private let minimumShareOnKey: Float = 0.6
/// Fewest slots with lines in each outermost row and column.
private let minimumSlotsOnEachEdge = 2

/// A line's face center, at a whole column and row of the grid.
private typealias Member = (point: Point, position: SIMD2<Int>)

/// The grid of the key the lines are on, its slots the key's 25 dice; nil when the lines do not
/// make one.
///
/// The step between dice is the median distance from each face to its nearest neighbor on
/// another die, and rows run in the direction the lines share, within 45 degrees of the frame's
/// x axis, so row 0 is the top of the key as the camera sees it. Of the flat grids with that
/// step and a face at column 0 and row 0, the one with the most faces on whole columns and rows
/// is refitted to them, and the outermost columns and rows with too few lines to be part of the
/// key are dropped. With enough lines left it is refitted in perspective, gathering only lines
/// within a column or row of them, so dice farther out are not taken in. The grid is pinned to
/// the key when the lines left span exactly 5 columns and 5 rows, make up most of the lines,
/// and fill more than one slot of each outermost row and column: dice scattered or lying
/// beside the key rarely do all three.
func fitGrid(to lines: [Undoverline]) -> Grid? {
    guard lines.count >= minimumLinesOnGrid else { return nil }
    let centers = lines.map(\.faceCenter)
    let faceSize = median(lines.map(\.length))
    let neighbors = centers.compactMap { center in
        centers.map { simd_distance($0, center) }.filter { $0 > sameDieDistance * faceSize }.min()
    }
    guard neighbors.count >= minimumLinesOnGrid else { return nil }
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
    for _ in 0..<refits {
        guard let refit = grid.refitted(to: members(of: grid), perspective: false) else { return nil }
        grid = refit
    }

    var onKey = withoutStrays(members(of: grid))
    if onKey.count >= minimumLinesForPerspective {
        let (low, high) = extent(of: onKey)
        for _ in 0..<refits {
            guard let refit = grid.refitted(to: onKey, perspective: true) else { break }
            grid = refit
            onKey = members(of: grid).filter { all($0.position .>= low &- 1 .& $0.position .<= high &+ 1) }
        }
    }
    onKey = withoutStrays(onKey)

    guard onKey.count >= minimumLinesOnGrid, Float(onKey.count) >= minimumShareOnKey * Float(lines.count) else {
        return nil
    }
    let (low, high) = extent(of: onKey)
    let slots = Set(onKey.map(\.position))
    guard high &- low == SIMD2(repeating: 4),
        [low, high].allSatisfy({ edge in
            (0..<2).allSatisfy { axis in slots.count(where: { $0[axis] == edge[axis] }) >= minimumSlotsOnEachEdge }
        })
    else { return nil }
    return grid.shifted(by: low)
}

/// The members less the outermost columns, then rows, that hold too few lines to be part of the
/// key, while they span more than 5. Of the two ends, the one with fewer lines goes, the lower
/// on a tie; when both hold more than `maximumStrayLines`, the rest stay.
private func withoutStrays(_ members: [Member]) -> [Member] {
    var members = members
    for axis in 0..<2 {
        while let low = members.map({ $0.position[axis] }).min(), let high = members.map({ $0.position[axis] }).max(),
            high - low > 4
        {
            let lowCount = members.count(where: { $0.position[axis] == low })
            let highCount = members.count(where: { $0.position[axis] == high })
            guard min(lowCount, highCount) <= maximumStrayLines else { break }
            let cut = lowCount <= highCount ? low : high
            members.removeAll { $0.position[axis] == cut }
        }
    }
    return members
}

/// The lowest and the highest column and row of the members, of which there is at least one.
private func extent(of members: [Member]) -> (low: SIMD2<Int>, high: SIMD2<Int>) {
    let positions = members.map(\.position)
    return (positions.reduce(positions[0], pointwiseMin), positions.reduce(positions[0], pointwiseMax))
}
