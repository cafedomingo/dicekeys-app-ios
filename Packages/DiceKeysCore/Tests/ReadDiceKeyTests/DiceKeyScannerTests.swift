//
//  DiceKeyScannerTests.swift
//  ReadDiceKeyTests
//

import Foundation
import Testing
@testable import ReadDiceKey

@Suite("DiceKeyScanner smoke tests")
struct DiceKeyScannerTests {
    @Test("a blank frame does not read as a DiceKey and does not crash")
    func blankFrame() {
        let scanner = DiceKeyScanner()
        let width = 64, height = 64
        let frame = Data(repeating: 0xFF, count: width * height * 4)
        #expect(scanner.process(rgba: frame, width: width, height: height) == false)
        #expect(scanner.isFinished == false)
        #expect(!scanner.readResultJSON.isEmpty)
        #expect(scanner.renderOverlay(width: width, height: height).count == width * height * 4)
    }
}
