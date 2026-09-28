//
//  UndoverlineTests.swift
//  ReadDiceKeyTests
//

import Testing
@testable import ReadDiceKey

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
