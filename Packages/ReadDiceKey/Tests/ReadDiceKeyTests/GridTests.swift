//
//  GridTests.swift
//  ReadDiceKeyTests
//

import CoreGraphics
import Testing
import simd

@testable import ReadDiceKey

@Suite("Grid geometry")
struct GridGeometryTests {
    private let flat = Grid(origin: Point(100, 100), across: Point(200, 0), down: Point(0, 200))

    /// Where (column, row) lies under a perspective map whose dice shrink toward the bottom right.
    private func tilted(_ position: SIMD2<Int>) -> Point {
        let map = simd_double3x3(rows: [SIMD3(160, 20, 100), SIMD3(-10, 150, 140), SIMD3(0.06, 0.03, 1)])
        let point = map * SIMD3(Double(position.x), Double(position.y), 1)
        return Point(Float(point.x / point.z), Float(point.y / point.z))
    }

    @Test("refitted with perspective to the exact points of a perspective map, a flat grid becomes that map")
    func refitReproducesPerspective() throws {
        let members = (0..<25).map { index in
            let position = SIMD2(index % 5, index / 5)
            return (point: tilted(position), position: position)
        }
        let grid = try #require(flat.refitted(to: members, perspective: true))
        for column in -1...5 {
            for row in -1...5 {
                #expect(
                    simd_distance(grid.point(at: SIMD2(Float(column), Float(row))), tilted(SIMD2(column, row))) < 0.01)
            }
        }
    }

    @Test("cannot be refitted to points in one row")
    func refitNeedsTwoRows() {
        let row = (0..<5).map { (point: flat.point(at: SIMD2(Float($0), 0)), position: SIMD2($0, 0)) }
        #expect(flat.refitted(to: row, perspective: false) == nil)
        #expect(flat.refitted(to: row, perspective: true) == nil)
    }

    @Test("a point is in the slot within a quarter step of it along each axis, in columns and rows 0 to 4")
    func slotOfPoint() {
        #expect(flat.slot(of: flat.point(at: SIMD2(2.24, 2.76))) == 17)
        #expect(flat.slot(of: flat.point(at: SIMD2(2.26, 3))) == nil)
        #expect(flat.slot(of: flat.point(at: SIMD2(2, 3.26))) == nil)
        #expect(flat.slot(of: flat.point(at: SIMD2(0, 0))) == 0)
        #expect(flat.slot(of: flat.point(at: SIMD2(4, 4))) == 24)
        #expect(flat.slot(of: flat.point(at: SIMD2(5, 2))) == nil)
        #expect(flat.slot(of: flat.point(at: SIMD2(2, -1))) == nil)
        #expect(flat.nearestPosition(to: flat.point(at: SIMD2(5, -1))) == SIMD2(5, -1))
    }
}

@Suite("Grid")
struct GridTests {
    private let key = SyntheticDiceKey.sample
    private let side = 1080
    /// From one die to the next in the synthetic frames.
    private var pitch: Double { Double(side) / 6 }
    private var leftColumn: Set<Int> { [0, 5, 10, 15, 20] }

    @Test("reads a key with no row or column whose every die is in view")
    func readsWithoutACompleteRow() {
        let diagonal: Set<Int> = [0, 6, 12, 18, 24]
        var scanner = DiceKeyScanner()
        scanner.scan(key.image(side: side, hiding: diagonal))
        #expect(scanner.faces == (0..<25).map { diagonal.contains($0) ? nil : key.faces[$0] })
    }

    @Test("reads the dice in view of a key whose left column is cut in half by the frame")
    func readsAKeyCutOffAtTheSide() {
        var scanner = DiceKeyScanner()
        scanner.scan(key.image(side: side, offset: CGVector(dx: -pitch, dy: 0)))
        #expect(scanner.faces == (0..<25).map { leftColumn.contains($0) ? nil : key.faces[$0] })
    }

    @Test("reads a key tilted away from the camera")
    func readsATiltedKey() {
        var scanner = DiceKeyScanner()
        scanner.scan(key.image(side: side).tilted(topWidth: 0.7))
        #expect(scanner.diceKey == key.faces)
    }

    @Test("reads a key beside a die beyond its edge")
    func readsBesideAStrayDie() {
        var scanner = DiceKeyScanner()
        scanner.scan(
            key.image(
                side: side, offset: CGVector(dx: -pitch / 2, dy: 0),
                strays: [(column: 5, row: 2, face: key.withOtherDigits.faces[0])]))
        #expect(scanner.diceKey == key.faces)
    }

    @Test(
        "a key whose left column is out of view, beside a die beyond its right edge, reads nothing rather than a column off"
    )
    func refusesAStrayInPlaceOfAColumn() {
        var scanner = DiceKeyScanner()
        scanner.scan(
            key.image(
                side: side, offset: CGVector(dx: -1.5 * pitch, dy: 0),
                strays: [(column: 5, row: 2, face: key.withOtherDigits.faces[0])]))
        #expect(scanner.faces.allSatisfy { $0 == nil })
    }

    @Test("reads nothing from dice scattered on a table")
    func readsNothingFromScatteredDice() {
        var scanner = DiceKeyScanner()
        #expect(scanner.scan(key.scatteredImage(side: side)).isEmpty)
    }
}
