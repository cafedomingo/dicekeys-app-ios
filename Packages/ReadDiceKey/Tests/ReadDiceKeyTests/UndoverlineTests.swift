//
//  UndoverlineTests.swift
//  ReadDiceKeyTests
//

import DiceKeySpecification
import Testing

@testable import ReadDiceKey

@Suite("twoLevelThreshold")
struct ThresholdTests {
    @Test("splits halfway between the darkest light sample and the lightest dark one")
    func splitsTwoGroups() {
        #expect(twoLevelThreshold([10, 12, 11, 9, 200, 190, 210, 205]) == 101)
    }

    @Test("puts the split where the groups are tightest")
    func findsTightestSplit() {
        #expect(twoLevelThreshold([10, 20, 30, 40, 100, 180, 190, 200, 210, 220]) == 140)
    }

    @Test("keeps at least four samples on each side")
    func honorsMinimumCounts() {
        #expect(twoLevelThreshold([10, 200, 200, 200, 200, 200, 200, 200]) == 200)
    }
}

@Suite("readUndoverline")
struct ReadUndoverlineTests {
    /// The underline of A1 reads, from its letter end, 1 0 0000 0111 0: these are its dark dots
    /// and its light dots, in order.
    private let darkDots = [1, 2, 3, 4, 5, 6, 10]
    private let lightDots = [0, 7, 8, 9]

    /// A light frame holding A1's underline, 220 pixels long and level, its ink at 20 and each dot
    /// at the brightness given for it, in the order of `darkDots` and `lightDots`.
    private func underline(dark: [UInt8], light: [UInt8]) -> (image: GrayImage, bar: Bar) {
        let bar = Bar(center: Point(150, 50), axis: Point(1, 0), length: 220, width: 39)
        let start = bar.center.x - bar.length / 2
        let dotHalfWidth = bar.length * Float(FaceDimensionsFractional.undoverlineDotWidth) / 2
        var levels = [UInt8](repeating: 0, count: 11)
        for (dot, level) in zip(darkDots + lightDots, dark + light) {
            levels[dot] = level
        }
        var pixels = [UInt8](repeating: 240, count: 300 * 100)
        for y in 0..<100 {
            for x in 0..<300 where bar.contains(Point(Float(x), Float(y))) {
                pixels[y * 300 + x] = 20
                for (dot, fraction) in FaceDimensionsFractional.dotCentersAsFractionOfUndoverline.enumerated() {
                    let dotX = start + bar.length * Float(fraction)
                    if abs(Float(x) - dotX) <= dotHalfWidth, abs(Float(y) - bar.center.y) <= dotHalfWidth {
                        pixels[y * 300 + x] = levels[dot]
                    }
                }
            }
        }
        return (GrayImage(width: 300, height: 100, pixels: pixels), bar)
    }

    @Test("reads a bar whose dots split cleanly into dark and light")
    func readsCleanDots() throws {
        let (image, bar) = underline(dark: [20, 30, 40, 50, 60, 70, 40], light: [190, 200, 210, 200])
        let line = try #require(readUndoverline(in: image, bar: bar))
        #expect(line.bits.face?.letter == .A && line.bits.face?.digit == ._1 && !line.bits.isOverline)
    }

    @Test("does not read a bar whose darkest light dot is barely lighter than its lightest dark one")
    func refusesDotsThatBarelySplit() {
        let (image, bar) = underline(dark: [20, 30, 40, 50, 60, 70, 100], light: [120, 190, 200, 210])
        #expect(readUndoverline(in: image, bar: bar) == nil)
    }
}
