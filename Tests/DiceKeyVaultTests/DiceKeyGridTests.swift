//
//  DiceKeyGridTests.swift
//  DiceKeyVaultTests
//

import CoreGraphics
import Testing

@testable import DiceKeyVault

@MainActor
@Suite("DiceKey grid size")
struct DiceKeyGridTests {
    @Test("the grid is as tall as the dice, their gaps and the box around them")
    func extentOfTheStandardGrid() {
        #expect(abs(DiceKeyGrid.extent(dieSize: DieView.Size.grid) - 278.08) < 0.01)
    }

    @Test("dice sized to fit an extent fill it exactly")
    func fittingFillsTheExtent() {
        for extent: CGFloat in [150, 200, 278.08] {
            #expect(abs(DiceKeyGrid.extent(dieSize: DiceKeyGrid.dieSize(fitting: extent)) - extent) < 0.001)
        }
    }
}
