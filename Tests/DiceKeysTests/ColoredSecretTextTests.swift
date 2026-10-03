//
//  ColoredSecretTextTests.swift
//  DiceKeysTests
//

import Testing

@testable import DiceKeys

@Suite("Glyph classes for coloring a secret")
struct ColoredSecretTextTests {
    @Test("digits, symbols and the rest")
    func classes() {
        #expect(SecretGlyph.classify("7") == .digit)
        #expect(SecretGlyph.classify("a") == .plain)
        #expect(SecretGlyph.classify("Q") == .plain)
        #expect(SecretGlyph.classify("-") == .symbol)
        #expect(SecretGlyph.classify("?") == .symbol)
        #expect(SecretGlyph.classify("_") == .symbol)
        #expect(SecretGlyph.classify(" ") == .plain)
    }

    @Test("emoji stay plain")
    func emojiStayPlain() {
        #expect(SecretGlyph.classify("🐶") == .plain)
        #expect(SecretGlyph.classify("⌚") == .plain)
    }
}
