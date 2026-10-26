//
//  KeyRecipeTests.swift
//  DerivationTests
//

import Foundation
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

@Test func recipeText() throws {
    #expect(try KeyRecipe(kind: .ssh, name: "github").json == #"{"kind":"ssh","name":"github"}"#)
    #expect(try KeyRecipe(kind: .wallet, name: #"a "b" \c"#).json == #"{"kind":"wallet","name":"a \"b\" \\c"}"#)
    #expect(
        try KeyRecipe(kind: .passphrase, name: "nas").json
            == #"{"kind":"passphrase","length":24,"list":"letters-digits","name":"nas"}"#)
    #expect(
        try KeyRecipe(kind: .passphrase, name: "nas", style: .memorable(words: 6, digitsAndUppercase: true)).json
            == #"{"kind":"passphrase","length":6,"list":"eff_large_wordlist","name":"nas","separator":"digits","uppercase":true}"#
    )
}

@Test func styleOnlyOnPassphrases() throws {
    #expect(
        try KeyRecipe(kind: .age, name: "backup", style: .memorable(words: 6, digitsAndUppercase: false)).style == nil)
    #expect(throws: KeyRecipeError.styleOutOfRange) {
        try KeyRecipe(kind: .passphrase, name: "nas", style: .random(length: 11, symbols: false))
    }
    #expect(throws: KeyRecipeError.styleOutOfRange) {
        try KeyRecipe(kind: .passphrase, name: "nas", style: .memorable(words: 11, digitsAndUppercase: false))
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
    #expect(quotedJsonString("a\"b\\c\u{1}\n\u{7F}é") == #""a\"b\\c\u0001\n\#u{7F}é""#)
    #expect(
        CanonicalJSON.object(["\u{FB33}": .integer(1), "\u{1F600}": .boolean(true), "a": .string("x")])
            == "{\"a\":\"x\",\"\u{1F600}\":true,\"\u{FB33}\":1}")
}

/// Recipe text is accepted only as the exact canonical text of a recipe, because the text is
/// what gets hashed: any other spelling of the same recipe would derive a different key.
@Test(arguments: [
    #" {"kind":"ssh","name":"github"}"#,
    #"{"kind": "ssh","name":"github"}"#,
    #"{"name":"github","kind":"ssh"}"#,
    #"{"kind":"ssh","name":"github","name":"github"}"#,
    #"{"kind":"ssh","name":"\u0067ithub"}"#,
    #"{"kind":"ssh","name":" github"}"#,
    #"{"kind":"ssh","name":"cafe\#u{0301}"}"#,
    #"{"kind":"ssh","name":""}"#,
    #"{"kind":"pgp","name":"github"}"#,
    #"{"purpose":"ssh:github"}"#,
    #"{"kind":"ssh","name":"github","type":"SigningKey"}"#,
    #"{"kind":"ssh","name":"github","purpose":"x"}"#,
    #"{"kind":"ssh","length":24,"name":"github"}"#,
    #"{"kind":"ssh","list":"letters-digits","name":"github"}"#,
    #"{"kind":"passphrase","name":"nas"}"#,
    #"{"kind":"passphrase","length":24,"name":"nas"}"#,
    #"{"kind":"passphrase","list":"letters-digits","name":"nas"}"#,
    #"{"kind":"passphrase","length":24.0,"list":"letters-digits","name":"nas"}"#,
    #"{"kind":"passphrase","length":11,"list":"letters-digits","name":"nas"}"#,
    #"{"kind":"passphrase","length":65,"list":"letters-digits","name":"nas"}"#,
    #"{"kind":"passphrase","length":24,"list":"letters","name":"nas"}"#,
    #"{"kind":"passphrase","length":24,"list":"letters-digits","name":"nas","separator":"-"}"#,
    #"{"kind":"passphrase","length":24,"list":"letters-digits","name":"nas","uppercase":true}"#,
    #"{"kind":"passphrase","length":6,"list":"eff_large_wordlist","name":"nas"}"#,
    #"{"kind":"passphrase","length":3,"list":"eff_large_wordlist","name":"nas","separator":"-"}"#,
    #"{"kind":"passphrase","length":6,"list":"eff_large_wordlist","name":"nas","separator":"-","uppercase":true}"#,
    #"{"kind":"passphrase","length":6,"list":"eff_large_wordlist","name":"nas","separator":"digits"}"#,
    #"{"kind":"passphrase","length":6,"list":"eff_large_wordlist","name":"nas","separator":"-","uppercase":false}"#,
    #"{"capitalize":true,"kind":"passphrase","length":6,"list":"eff_large_wordlist","name":"nas","separator":"digits"}"#,
    #"{"kind":"passphrase","length":6,"list":"eff_large_wordlist","name":"nas","separator":" "}"#,
    #"{"kind":"passphrase","lengthInChars":24,"name":"nas","wordList":"CHARS_57_letters_digits_20261002"}"#,
    #"["ssh","github"]"#,
    #"{"kind":"ssh","name":"github"} "#,
    ""
])
func nonCanonicalRecipesAreRejected(_ text: String) {
    #expect(throws: KeyRecipeError.notARecipe) { try KeyRecipe(json: text) }
}

@Test func canonicalRecipesParse() throws {
    let memorable = try KeyRecipe(kind: .passphrase, name: "nas", style: .memorable(words: 6, digitsAndUppercase: true))
    #expect(try KeyRecipe(json: memorable.json) == memorable)
    let random = try KeyRecipe(kind: .passphrase, name: "nas", style: .random(length: 64, symbols: true))
    #expect(try KeyRecipe(json: random.json) == random)
    #expect(try KeyRecipe(json: #"{"kind":"ssh","name":"a \"b\" \\c"}"#).name == #"a "b" \c"#)
}

/// The fields of a catalog or paper key are held to the same rules as recipe text: a name
/// that isn't already normalized is refused, not quietly normalized.
@Test func decodedFieldsMustBeCanonical() throws {
    let decoder = JSONDecoder()
    #expect(try decoder.decode(KeyRecipe.self, from: Data(#"{"name":"github","kind":"ssh"}"#.utf8)).name == "github")
    #expect(throws: KeyRecipeError.notARecipe) {
        try decoder.decode(KeyRecipe.self, from: Data(#"{"kind":"ssh","name":"cafe\#u{0301}"}"#.utf8))
    }
}

@Test func defaultRecipesArePinned() throws {
    #expect(KeyRecipe.defaults.map(\.json) == [#"{"kind":"ssh"}"#, #"{"kind":"age"}"#])
    for recipe in KeyRecipe.defaults {
        #expect(recipe.isDefault && recipe.name == nil && recipe.style == nil)
        #expect(try KeyRecipe(json: recipe.json) == recipe)
        #expect(try JSONDecoder().decode(KeyRecipe.self, from: Data(recipe.json.utf8)) == recipe)
        #expect(recipe.fieldNames == ["kind"])
    }
    #expect(try !KeyRecipe(kind: .ssh, name: "github").isDefault)
}

@Test(arguments: [
    #"{"kind":"passphrase"}"#, #"{"kind":"wallet"}"#, #"{"kind":"wireguard"}"#, #"{"kind":"ssh","length":24}"#,
    #"{ "kind":"ssh" }"#, #"{"kind":"ssh","name":""}"#, #"{"kind":"SSH"}"#
])
func namelessRecipesOtherThanDefaultsAreRejected(_ text: String) {
    #expect(throws: KeyRecipeError.notARecipe) { try KeyRecipe(json: text) }
}

@Test func defaultSSHLineHasNoComment() {
    let seed = "A1tB2rC3bD4lE5tF6rG1bH2lI3tJ4rK5bL6lM1tN2rO3bP4lR5tS6rT1bU2lV3tW4rX5bY6lZ1t"
    let line = DerivedKey.derive(seed: seed, recipe: KeyRecipe.defaults[0]).publicKey ?? ""
    #expect(line.split(separator: " ", omittingEmptySubsequences: false).count == 2)
}
