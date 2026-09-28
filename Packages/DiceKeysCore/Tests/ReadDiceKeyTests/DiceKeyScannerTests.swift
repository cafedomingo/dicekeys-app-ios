//
//  DiceKeyScannerTests.swift
//  ReadDiceKeyTests
//

import Foundation
import Testing
@testable import ReadDiceKey

@Suite("DiceKeyScanner")
struct DiceKeyScannerTests {
    private let key = SyntheticDiceKey.sample
    private let topLeftBlock: Set<Int> = [0, 1, 5, 6]
    private let bottomRightBlock: Set<Int> = [18, 19, 23, 24]

    @Test("a blank frame reads nothing")
    func blankFrame() {
        var scanner = DiceKeyScanner()
        #expect(scanner.scan(GrayImage(width: 64, height: 64, pixels: [UInt8](repeating: 255, count: 64 * 64))).isEmpty)
        #expect(scanner.diceKey == nil)
    }

    @Test("a frame of noise reads nothing")
    func noiseFrame() {
        var generator = SystemRandomNumberGenerator()
        let pixels = (0..<(540 * 540)).map { _ in UInt8.random(in: 0...255, using: &generator) }
        var scanner = DiceKeyScanner()
        scanner.scan(GrayImage(width: 540, height: 540, pixels: pixels))
        #expect(scanner.faces.allSatisfy { $0 == nil })
        #expect(scanner.diceKey == nil)
    }

    @Test("reads every face of a key from its bars in one frame", arguments: [540, 1080])
    func readsSyntheticKey(side: Int) {
        var scanner = DiceKeyScanner()
        let dice = scanner.scan(key.image(side: side))
        #expect(scanner.diceKey == key.faces)
        #expect(dice.count == 25)
        #expect(dice.allSatisfy { $0.face != nil })
    }

    @Test("reports where each die is")
    func placesDice() throws {
        var scanner = DiceKeyScanner()
        let dice = scanner.scan(key.image(side: 1080, rotation: 0))
        let center = try #require(dice.first { $0.face == key.faces[12] })
        #expect(abs(center.center.x - 540) < 10 && abs(center.center.y - 540) < 10)
        // Faces are half the 180-pixel pitch; the reading direction is the face's turns.
        #expect(abs(center.size - 90) < 5)
        let expectedAngle = Double(key.faces[12].clockwiseTurns) * .pi / 2
        #expect(abs(remainder(center.angle - expectedAngle, 2 * .pi)) < 0.05)
    }

    @Test("a quarter turn of the key between frames merges")
    func quarterTurnMerges() {
        var scanner = DiceKeyScanner()
        scanner.scan(key.image(side: 1080, hiding: topLeftBlock))
        #expect(scanner.diceKey == nil)
        scanner.scan(key.turnedClockwise.image(side: 1080, hiding: bottomRightBlock))
        #expect(scanner.diceKey == key.turnedClockwise.faces)
    }

    @Test("a frame that reads nothing keeps what was read")
    func emptyFrameKeepsFaces() {
        var scanner = DiceKeyScanner()
        scanner.scan(key.image(side: 1080, hiding: topLeftBlock))
        scanner.scan(GrayImage(width: 1080, height: 1080, pixels: [UInt8](repeating: 30, count: 1080 * 1080)))
        scanner.scan(key.image(side: 1080, hiding: bottomRightBlock))
        #expect(scanner.diceKey == key.faces)
    }

    @Test("a second key that shares one face with the first is not mixed into it")
    func oneSharedFaceDoesNotMerge() {
        // Only the top-left and center dice of the first key are read.
        var scanner = DiceKeyScanner()
        scanner.scan(key.image(side: 1080, unreadable: Set(0..<25).subtracting([0, 12])))
        #expect(scanner.faces.compactMap { $0 }.count == 2)
        // A different key with the same center face, whose top-left die goes unread.
        let other = key.withOtherDigits.replacingFace(at: 12, with: key.faces[12])
        scanner.scan(other.image(side: 1080, unreadable: [0]))
        #expect(scanner.diceKey == nil)
        #expect(scanner.faces[0] == nil)
        scanner.scan(other.image(side: 1080))
        #expect(scanner.diceKey == other.faces)
    }

    @Test("a frame that cannot be lined up with what is known shows only what it read")
    func unalignedFrameShowsItsOwnReads() {
        var scanner = DiceKeyScanner()
        scanner.scan(key.image(side: 1080, hiding: topLeftBlock))
        let dice = scanner.scan(key.turnedClockwise.image(side: 1080, unreadable: Set(0..<25)))
        #expect(dice.count == 25)
        #expect(dice.allSatisfy { $0.face == nil })
        #expect(scanner.faces.compactMap { $0 }.count == 21)
    }

    @Test("a different key starts over")
    func differentKeyStartsOver() {
        var scanner = DiceKeyScanner()
        scanner.scan(key.image(side: 1080, hiding: topLeftBlock))
        let other = key.withOtherDigits
        scanner.scan(other.image(side: 1080, hiding: bottomRightBlock))
        #expect(scanner.diceKey == nil)
        #expect(scanner.faces.compactMap { $0 }.count == 21)
        scanner.scan(other.image(side: 1080, hiding: topLeftBlock))
        #expect(scanner.diceKey == other.faces)
    }
}

@Suite("twoLevelThreshold")
struct ThresholdTests {
    @Test("splits halfway between the darkest light sample and the lightest dark one")
    func splitsTwoGroups() {
        #expect(twoLevelThreshold([10, 12, 11, 9, 200, 190, 210, 205], minDark: 4, minLight: 4) == 101)
    }

    @Test("puts the split where the groups are tightest")
    func findsTightestSplit() {
        #expect(twoLevelThreshold([10, 20, 30, 100, 180, 190, 200, 210, 220, 230], minDark: 1, minLight: 1) == 140)
    }

    @Test("keeps at least the minimum number of samples on each side")
    func honorsMinimumCounts() {
        #expect(twoLevelThreshold([10, 200, 200, 200, 200, 200, 200, 200], minDark: 4, minLight: 4) == 200)
    }
}
