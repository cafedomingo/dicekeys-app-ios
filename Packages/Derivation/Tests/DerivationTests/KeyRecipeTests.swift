//
//  KeyRecipeTests.swift
//  DerivationTests
//

import Testing

@testable import Derivation
@testable import KeyFormats

@Test(arguments: [
    ("github", "github"),
    ("  github\t\n", "github"),
    ("\u{3000}homelab\u{00A0}", "homelab"),
    ("cafe\u{0301}", "caf\u{00E9}"),
    ("Mixed Case", "Mixed Case"),
    ("inner  spaces", "inner  spaces")
])
func nameIsTrimmedAndNormalized(_ input: String, _ expected: String) throws {
    #expect(try KeyRecipe.normalizedName(input) == expected)
}

@Test func nameErrors() {
    #expect(throws: KeyRecipeError.emptyName) { try KeyRecipe.normalizedName(" \u{2003} ") }
    #expect(throws: KeyRecipeError.controlCharacterInName) { try KeyRecipe.normalizedName("a\u{0007}b") }
    #expect(throws: KeyRecipeError.controlCharacterInName) { try KeyRecipe.normalizedName("a\u{0085}b") }
    #expect(throws: KeyRecipeError.nameTooLong(65)) { try KeyRecipe.normalizedName(String(repeating: "x", count: 65)) }
    #expect(throws: Never.self) { try KeyRecipe.normalizedName(String(repeating: "é", count: 64)) }
}

/// Characters that print as nothing would make a name that looks right on paper derive a different
/// key, and a character no version of Unicode has assigned yet could normalize differently once
/// one does.
@Test(arguments: [
    "github\u{200B}", "\u{FEFF}github", "git\u{200E}hub", "git\u{202E}hub", "git\u{2060}hub"
])
func invisibleCharactersAreRejected(_ name: String) {
    #expect(throws: KeyRecipeError.invisibleCharacterInName) { try KeyRecipe.normalizedName(name) }
}

@Test func unassignedCharactersAreRejected() {
    #expect(throws: KeyRecipeError.unassignedCharacterInName) { try KeyRecipe.normalizedName("a\u{0378}b") }
}

@Test func joinersInEmojiAreKept() throws {
    let technologist = "\u{1F469}\u{200D}\u{1F4BB}"
    #expect(try KeyRecipe.normalizedName(technologist) == technologist)
    #expect(try KeyRecipe.normalizedName("\u{2764}\u{FE0F}") == "\u{2764}\u{FE0F}")
}

@Test func templates() throws {
    #expect(try KeyRecipe(kind: .ssh, name: "github").json == #"{"purpose":"ssh:github"}"#)
    #expect(try KeyRecipe(kind: .wallet, name: #"a "b" \c"#).json == #"{"purpose":"wallet:a \"b\" \\c"}"#)
    #expect(
        try KeyRecipe(kind: .passphrase, name: "nas").json
            == #"{"lengthInChars":24,"purpose":"passphrase:nas","wordList":"CHARS_57_letters_digits_20261002"}"#)
    #expect(
        try KeyRecipe(kind: .passphrase, name: "nas", style: .memorable(words: 6, digitAndCapital: true)).json
            == #"{"capitalize":true,"lengthInWords":6,"purpose":"passphrase:nas","separator":"digits","wordList":"EFF_large_7776_words_9_chars_max_20160719"}"#
    )
}

@Test func styleOnlyOnPassphrases() throws {
    #expect(try KeyRecipe(kind: .age, name: "backup", style: .memorable(words: 6, digitAndCapital: false)).style == nil)
    #expect(throws: KeyRecipeError.styleOutOfRange) {
        try KeyRecipe(kind: .passphrase, name: "nas", style: .random(length: 11, symbols: false))
    }
    #expect(throws: KeyRecipeError.styleOutOfRange) {
        try KeyRecipe(kind: .passphrase, name: "nas", style: .memorable(words: 11, digitAndCapital: false))
    }
}

/// BIP 173's valid test string `abcdef1qpzry9x8gf2tvdw0s3jn54khce6mua7lmqqqxw` carries the
/// 5-bit values 0 to 31 in order.
@Test func bech32Checksum() {
    let values = (0..<32).map { UInt8($0) }
    let checksum = Bech32.checksum(hrp: "abcdef", values: values)
    let alphabet = Array("qpzry9x8gf2tvdw0s3jn54khce6mua7l")
    #expect(String(checksum.map { alphabet[Int($0)] }) == "mqqqxw")
}

@Test func bech32Regroup() {
    #expect(Bech32.regroup([0xFF]) == [31, 28])
    #expect(Bech32.regroup([0x00, 0x01]) == [0, 0, 0, 16])
}

/// RFC 8785 section 3.2.2.2 escaping and section 3.2.3 ordering by UTF-16 code units, under
/// which U+1F600 (a surrogate pair starting 0xD83D) sorts before U+FB33.
@Test func canonicalJSON() {
    #expect(CanonicalJSON.string("a\"b\\c\u{1}\n\u{7F}é") == #""a\"b\\c\u0001\n\#u{7F}é""#)
    #expect(
        CanonicalJSON.object(["\u{FB33}": .integer(1), "\u{1F600}": .boolean(true), "a": .string("x")])
            == "{\"a\":\"x\",\"\u{1F600}\":true,\"\u{FB33}\":1}")
}
