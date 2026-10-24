//
//  Grid.swift
//  ReadDiceKey
//
//  The grid of the key as it lies in the frame: a perspective map from columns and rows to
//  frame pixels, the slots on it, and refitting the map to points at known columns and rows.
//

import simd

/// How far from a whole column and row, in steps along each axis, a face's center may be and still be in that slot.
private let slotTolerance: Float = 0.25

/// The smallest pivot the least-squares fit divides by; a smaller one means its points cannot fix the map.
private let smallestPivot = 1e-9

/// The grid of dice as it lies in the frame: a map, flat or in perspective, from columns and rows
/// to frame pixels, whole columns and rows at the dice's middles. Pinned to a key, its slots are
/// columns and rows 0 to 4, row 0 at the top.
struct Grid: Sendable {
    /// From (column, row, 1) to frame pixels, in homogeneous coordinates.
    private let toFrame: simd_double3x3
    private let fromFrame: simd_double3x3

    private init(toFrame: simd_double3x3) {
        self.toFrame = toFrame
        fromFrame = toFrame.inverse
    }

    /// A flat grid with column 0 and row 0 at `origin`, `across` from one column to the next and
    /// `down` from one row to the next.
    init(origin: Point, across: Point, down: Point) {
        self.init(
            toFrame: simd_double3x3(rows: [
                SIMD3(Double(across.x), Double(down.x), Double(origin.x)),
                SIMD3(Double(across.y), Double(down.y), Double(origin.y)),
                SIMD3(0, 0, 1)
            ]))
    }

    /// Where the fractional (column, row) `position` lies in the frame.
    func point(at position: SIMD2<Float>) -> Point {
        let point = toFrame * SIMD3(Double(position.x), Double(position.y), 1)
        return Point(Float(point.x / point.z), Float(point.y / point.z))
    }

    /// The fractional (column, row) at `point` in the frame.
    func position(of point: Point) -> SIMD2<Float> {
        let position = fromFrame * SIMD3(Double(point.x), Double(point.y), 1)
        return SIMD2(Float(position.x / position.z), Float(position.y / position.z))
    }

    /// The whole (column, row) within `slotTolerance` of `point` along each axis, on the key or beyond it.
    func nearestPosition(to point: Point) -> SIMD2<Int>? {
        let position = position(of: point)
        let nearest = position.rounded(.toNearestOrAwayFromZero)
        let offset = position - nearest
        guard abs(offset.x) <= slotTolerance, abs(offset.y) <= slotTolerance,
            let column = Int(exactly: nearest.x), let row = Int(exactly: nearest.y)
        else { return nil }
        return SIMD2(column, row)
    }

    /// The index (row * 5 + column) of the slot `point` is in.
    func slot(of point: Point) -> Int? {
        guard let position = nearestPosition(to: point), (0...4).contains(position.x), (0...4).contains(position.y)
        else { return nil }
        return position.y * 5 + position.x
    }

    /// The middle of slot `slot`.
    func center(of slot: Int) -> Point {
        point(at: columnAndRow(of: slot))
    }

    /// The step from column to column at slot `slot`, from half a column before its middle to half a column after.
    func across(at slot: Int) -> Point {
        let position = columnAndRow(of: slot)
        return point(at: position + SIMD2(0.5, 0)) - point(at: position - SIMD2(0.5, 0))
    }

    /// The same grid, with (column, row) `origin` as column 0 and row 0.
    func shifted(by origin: SIMD2<Int>) -> Grid {
        Grid(
            toFrame: toFrame
                * simd_double3x3(rows: [
                    SIMD3(1, 0, Double(origin.x)), SIMD3(0, 1, Double(origin.y)), SIMD3(0, 0, 1)
                ]))
    }

    /// The grid fitted by least squares to points in the frame at known whole columns and rows,
    /// flat (keeping a flat grid flat) or in perspective; nil when the points cannot fix it, as
    /// when they lie in one line.
    ///
    /// The fit is of the correction from columns and rows to the points' positions on this grid,
    /// which are small numbers, rather than to frame pixels, so that the equations are well
    /// conditioned. It is linearized, the perspective map (a b c; d e f; g h 1) taking a point's
    /// column u and row v to x = (a u + b v + c) / (g u + h v + 1) and likewise y, multiplied out.
    func refitted(to members: [(point: Point, position: SIMD2<Int>)], perspective: Bool) -> Grid? {
        let unknowns = perspective ? 8 : 6
        var normal = [[Double]](repeating: [Double](repeating: 0, count: unknowns + 1), count: unknowns)
        for member in members {
            let onGrid = fromFrame * SIMD3(Double(member.point.x), Double(member.point.y), 1)
            let (x, y) = (onGrid.x / onGrid.z, onGrid.y / onGrid.z)
            let (u, v) = (Double(member.position.x), Double(member.position.y))
            let equations =
                perspective
                ? [[u, v, 1, 0, 0, 0, -x * u, -x * v, x], [0, 0, 0, u, v, 1, -y * u, -y * v, y]]
                : [[u, v, 1, 0, 0, 0, x], [0, 0, 0, u, v, 1, y]]
            for equation in equations {
                for i in 0..<unknowns {
                    for j in 0...unknowns {
                        normal[i][j] += equation[i] * equation[j]
                    }
                }
            }
        }
        guard let h = solve(normal) else { return nil }
        let correction = simd_double3x3(rows: [
            SIMD3(h[0], h[1], h[2]), SIMD3(h[3], h[4], h[5]), perspective ? SIMD3(h[6], h[7], 1) : SIMD3(0, 0, 1)
        ])
        return Grid(toFrame: toFrame * correction)
    }
}

/// The (column, row) of slot `slot`.
func columnAndRow(of slot: Int) -> SIMD2<Float> {
    SIMD2(Float(slot % 5), Float(slot / 5))
}

/// The solution of the linear equations whose coefficients and right-hand side are the rows of
/// `augmented`, by Gaussian elimination with partial pivoting; nil when they have no single solution.
private func solve(_ augmented: [[Double]]) -> [Double]? {
    var rows = augmented
    let count = rows.count
    for column in 0..<count {
        let pivot = (column..<count).max { abs(rows[$0][column]) < abs(rows[$1][column]) }!
        guard abs(rows[pivot][column]) >= smallestPivot else { return nil }
        rows.swapAt(column, pivot)
        for row in 0..<count where row != column {
            let factor = rows[row][column] / rows[column][column]
            for k in column...count {
                rows[row][k] -= factor * rows[column][k]
            }
        }
    }
    return (0..<count).map { rows[$0][count] / rows[$0][$0] }
}
