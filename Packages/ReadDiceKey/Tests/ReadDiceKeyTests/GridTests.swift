//
//  GridTests.swift
//  ReadDiceKeyTests
//

import CoreGraphics
import DiceKeySpecification
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
    private let leftColumn: Set<Int> = [0, 5, 10, 15, 20]
    /// The sample key with L4 at row 2, column 0, upside down so that its digit end is at the
    /// left. With the last three bits of both its codes dark, both bars name L3.
    private var keyWithL4AtTheLeft: SyntheticDiceKey {
        key.replacingFace(at: 10, with: ScannedFace(letter: .L, digit: ._4, clockwiseTurns: 2))
            .replacingFace(at: 11, with: ScannedFace(letter: .K, digit: ._3, clockwiseTurns: 1))
    }

    /// Whether every face read is the key's.
    private func readsOnly(_ key: SyntheticDiceKey, _ scanner: DiceKeyScanner) -> Bool {
        zip(scanner.faces, key.faces).allSatisfy { $0 == nil || $0 == $1 }
    }

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
        scanner.scan(key.image(side: side, offset: CGVector(dx: -pitch, dy: 0), printing: key.faces))
        #expect(readsOnly(key, scanner))
        #expect(key.faces.indices.allSatisfy { leftColumn.contains($0) || scanner.faces[$0] == key.faces[$0] })
    }

    /// Both bars of the die at row 2, column 0, placed where the grid puts them, run past the
    /// frame's edge, and the text the edge cuts off with them matches K1 rather than K3.
    @Test("a die the frame's edge cuts in half never completes another key")
    func refusesADieCutInHalfByTheFrame() {
        var scanner = DiceKeyScanner()
        scanner.scan(key.image(side: side, rotation: 0, hiding: [10], printing: key.faces))
        scanner.scan(key.image(side: side, offset: CGVector(dx: -pitch, dy: 0), printing: key.faces))
        #expect(readsOnly(key, scanner))
        #expect(scanner.diceKey == nil || scanner.diceKey == key.faces)
    }

    /// At 0.74, three dice of the bottom row have a bar that is not found, so their text has to
    /// confirm the other, read at the grid, and the size the other dice predict is too far off for it to.
    @Test("reads a key tilted away from the camera")
    func readsATiltedKey() {
        var scanner = DiceKeyScanner()
        scanner.scan(key.image(side: side).tilted(topWidth: 0.78))
        #expect(scanner.diceKey == key.faces)
    }

    @Test("a tilted key whose bottom row is out of view never reads a row off")
    func refusesATiltedKeyARowShort() {
        let image = key.image(side: side, offset: CGVector(dx: 0, dy: 1.5 * pitch), printing: key.faces)
        var scanner = DiceKeyScanner()
        scanner.scan(image.tilted(topWidth: 0.74))
        #expect(readsOnly(key, scanner))
    }

    /// Turned and tilted this steeply, the grid fitted to this key stretched over all five rows,
    /// and once pinned read six faces wrong.
    @Test("a key tilted so steeply that its grid stretches never reads wrong")
    func refusesAGridStretchedByASteepTilt() throws {
        let key = SyntheticDiceKey(
            faces: try #require(
                Corpus.faces(of: "O23C11Z10J51S50F52E31B43N60M23H53V31A53K12I33Y21W30U32G22L13P53R40D23T40X10")
            ).compactMap { $0 })
        var scanner = DiceKeyScanner()
        scanner.scan(key.image(side: side, rotation: 0.3, printing: key.faces).tilted(topWidth: 0.52))
        #expect(readsOnly(key, scanner))
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

    @Test(
        "a key whose left column shows only its top die, beside two dice beyond its right edge, never reads a column off"
    )
    func refusesTwoStraysBesideASparseColumn() {
        var scanner = DiceKeyScanner()
        scanner.scan(
            key.image(
                side: side, offset: CGVector(dx: -pitch / 2, dy: 0), hiding: [5, 10, 15, 20],
                strays: [
                    (column: 5, row: 1, face: key.withOtherDigits.faces[0]),
                    (column: 5, row: 3, face: key.withOtherDigits.faces[1])
                ]))
        #expect(readsOnly(key, scanner))
    }

    /// The cover darkens the last four dots of both bars of the die at row 2, column 0.
    @Test("a die whose bars a cover cuts short at the digit end never reads as another face")
    func refusesBarsCutShortByACover() {
        let key = keyWithL4AtTheLeft
        var scanner = DiceKeyScanner()
        scanner.scan(
            key.image(
                side: side, rotation: 0, printing: key.faces,
                covers: [CGRect(x: 0, y: 2.5 * pitch, width: 170, height: pitch)]))
        #expect(readsOnly(key, scanner))
        #expect(scanner.diceKey == nil || scanner.diceKey == key.faces)
    }

    /// The frame's edge cuts off the last four dots of both bars of the die at row 2, column 0.
    @Test("a die whose bars the frame's edge cuts short at the digit end never completes another key")
    func refusesBarsCutShortByTheFrame() {
        let key = keyWithL4AtTheLeft
        let cut = key.image(side: side, rotation: 0, offset: CGVector(dx: -172, dy: 0), printing: key.faces)
        var scanner = DiceKeyScanner()
        scanner.scan(cut)
        #expect(readsOnly(key, scanner))
        var merged = DiceKeyScanner()
        merged.scan(key.image(side: side, rotation: 0, hiding: [10], printing: key.faces))
        merged.scan(cut)
        #expect(merged.diceKey == nil || merged.diceKey == key.faces)
    }

    /// The frame's edge cuts a tenth off the digit end of both bars of the die at row 2, column 0,
    /// which is short enough to drop their last dots and long enough for both to be found as
    /// rectangles. Both then name the same wrong face, R5 for R4 or A5 for A4.
    @Test(
        "a die whose bars the frame's edge cuts a tenth short, found as rectangles, never completes another key",
        arguments: [(letter: FaceLetter.R, rotation: 0.015, dx: -138.0), (.A, -0.03, -139.0)]
    )
    func refusesBarsFoundShortByTheFrame(letter: FaceLetter, rotation: Double, dx: Double) {
        let edge = ScannedFace(letter: letter, digit: ._4, clockwiseTurns: 2)
        let moved = key.faces.firstIndex { $0.letter == letter }!
        let key = key.replacingFace(at: moved, with: key.faces[10]).replacingFace(at: 10, with: edge)
        var scanner = DiceKeyScanner()
        scanner.scan(key.image(side: side, rotation: rotation, hiding: [10], printing: key.faces))
        scanner.scan(
            key.image(side: side, rotation: rotation, offset: CGVector(dx: dx, dy: 0), printing: key.faces))
        #expect(readsOnly(key, scanner))
        #expect(scanner.diceKey == nil || scanner.diceKey == key.faces)
    }

    /// The band darkens the 7th to 9th dots of both bars of H5 at row 2, column 0, which turns
    /// it into F5 on both.
    @Test("a die crossed by a dark band over the same dots of both its bars never reads as another face")
    func refusesBarsCrossedByABand() {
        let key = key.replacingFace(at: 10, with: ScannedFace(letter: .H, digit: ._5, clockwiseTurns: 2))
            .replacingFace(at: 7, with: ScannedFace(letter: .K, digit: ._3, clockwiseTurns: 2))
        var scanner = DiceKeyScanner()
        scanner.scan(
            key.image(
                side: side, rotation: 0, printing: key.faces,
                covers: [CGRect(x: 156, y: 2.5 * pitch, width: 20, height: pitch)]))
        #expect(readsOnly(key, scanner))
    }

    @Test("reads nothing from dice scattered on a table")
    func readsNothingFromScatteredDice() {
        var scanner = DiceKeyScanner()
        #expect(scanner.scan(key.scatteredImage(side: side)).isEmpty)
    }
}
