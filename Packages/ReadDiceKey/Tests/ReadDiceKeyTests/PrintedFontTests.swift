//
//  PrintedFontTests.swift
//  ReadDiceKeyTests
//

import CoreText
import DiceKeySpecification
import Testing

@Suite("PrintedFont")
struct PrintedFontTests {
    @Test("can be drawn by its name, with nothing else to set up")
    func drawsByName() {
        let font = CTFontCreateWithName(PrintedFont.name as CFString, 12, nil)
        #expect(CTFontCopyPostScriptName(font) as String == PrintedFont.name)
    }
}
