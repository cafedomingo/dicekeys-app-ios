//
//  RecipeTests.swift
//  DerivationTests
//

import Derivation
import Testing

@Suite("Recipe parsing and validation")
struct RecipeTests {
    @Test("the empty recipe and the empty object take every default")
    func defaults() throws {
        for json in ["", "{}"] {
            let secret = try Recipe(json: json, type: .secret)
            #expect(secret.lengthInBytes == 32)
            #expect(secret.hashFunction == .blake2b)
            let password = try Recipe(json: json, type: .password)
            #expect(password.lengthInWords == 15)
            #expect(password.lengthInBytes == 120)
            #expect(password.lengthInChars == nil)
            #expect(password.wordList == .en512)
            for type in [DerivableType.symmetricKey, .unsealingKey, .signingKey] {
                #expect(try Recipe(json: json, type: type).lengthInBytes == 32)
            }
        }
    }

    @Test("the raw text is kept exactly")
    func keepsText() throws {
        let text = " {\"purpose\" : \"x\" }\n"
        #expect(try Recipe(json: text, type: .secret).json == text)
    }

    @Test("unknown fields are ignored")
    func unknownFields() throws {
        let recipe = try Recipe(
            json:
                ##"{"purpose":"x","#":2,"allow":[{"host":"*.example.com"}],"excludeOrientationOfFaces":true,"clientMayRetrieveKey":true,"hashFunctionMemoryLimitInBytes":8192,"zzz":[1,{"a":null}]}"##,
            type: .secret)
        #expect(recipe.lengthInBytes == 32)
    }

    @Test("a declared type must match the requested one")
    func typeField() throws {
        #expect(try Recipe(json: #"{"type":"Password"}"#, type: .password).type == .password)
        #expect(throws: DerivationError.typeMismatch(recipe: "Secret", requested: .password)) {
            try Recipe(json: #"{"type":"Secret"}"#, type: .password)
        }
        #expect(throws: DerivationError.typeMismatch(recipe: "bogus", requested: .secret)) {
            try Recipe(json: #"{"type":"bogus"}"#, type: .secret)
        }
        #expect(throws: DerivationError.wrongType(field: "type", expected: "a string")) {
            try Recipe(json: #"{"type":1}"#, type: .secret)
        }
    }

    @Test("each key type accepts only its own algorithm, and secrets and passwords accept none")
    func algorithmField() throws {
        #expect(try Recipe(json: #"{"algorithm":"XSalsa20Poly1305"}"#, type: .symmetricKey).lengthInBytes == 32)
        #expect(try Recipe(json: #"{"algorithm":"X25519"}"#, type: .unsealingKey).lengthInBytes == 32)
        #expect(try Recipe(json: #"{"algorithm":"Ed25519"}"#, type: .signingKey).lengthInBytes == 32)
        #expect(throws: DerivationError.invalidAlgorithm("X25519")) {
            try Recipe(json: #"{"algorithm":"X25519"}"#, type: .symmetricKey)
        }
        #expect(throws: DerivationError.invalidAlgorithm("Ed25519")) {
            try Recipe(json: #"{"algorithm":"Ed25519"}"#, type: .unsealingKey)
        }
        #expect(throws: DerivationError.invalidAlgorithm("X25519")) {
            try Recipe(json: #"{"algorithm":"X25519"}"#, type: .signingKey)
        }
        #expect(throws: DerivationError.invalidAlgorithm("X25519")) {
            try Recipe(json: #"{"algorithm":"X25519"}"#, type: .secret)
        }
        #expect(throws: DerivationError.invalidAlgorithm("bogus")) {
            try Recipe(json: #"{"algorithm":"bogus"}"#, type: .password)
        }
    }

    @Test("only BLAKE2b is a known hash function")
    func hashFunctionField() throws {
        #expect(try Recipe(json: #"{"hashFunction":"BLAKE2b"}"#, type: .secret).hashFunction == .blake2b)
        #expect(throws: DerivationError.unsupportedHashFunction("Argon2id")) {
            try Recipe(json: #"{"hashFunction":"Argon2id"}"#, type: .secret)
        }
        #expect(throws: DerivationError.unsupportedHashFunction("SHA256")) {
            try Recipe(json: #"{"hashFunction":"SHA256"}"#, type: .secret)
        }
    }

    @Test("secret length is 1 to 8160 bytes")
    func secretLength() throws {
        #expect(try Recipe(json: #"{"lengthInBytes":1}"#, type: .secret).lengthInBytes == 1)
        #expect(try Recipe(json: #"{"lengthInBytes":8160}"#, type: .secret).lengthInBytes == 8160)
        #expect(throws: DerivationError.outOfRange(field: "lengthInBytes", allowed: 1...8160)) {
            try Recipe(json: #"{"lengthInBytes":0}"#, type: .secret)
        }
        #expect(throws: DerivationError.outOfRange(field: "lengthInBytes", allowed: 1...8160)) {
            try Recipe(json: #"{"lengthInBytes":8192}"#, type: .secret)
        }
        #expect(throws: DerivationError.outOfRange(field: "lengthInBytes", allowed: 1...8160)) {
            try Recipe(json: #"{"lengthInBytes":4294967312}"#, type: .secret)
        }
    }

    @Test("integer fields must be JSON integers")
    func integerFields() {
        for json in [
            #"{"lengthInBytes":16.9}"#, #"{"lengthInBytes":true}"#, #"{"lengthInBytes":"16"}"#,
            #"{"lengthInBytes":null}"#, #"{"lengthInBytes":1e1}"#
        ] {
            #expect(throws: DerivationError.wrongType(field: "lengthInBytes", expected: "an integer")) {
                try Recipe(json: json, type: .secret)
            }
        }
        #expect(throws: DerivationError.wrongType(field: "lengthInChars", expected: "an integer")) {
            try Recipe(json: #"{"lengthInChars":8.9}"#, type: .password)
        }
        #expect(throws: DerivationError.outOfRange(field: "lengthInBytes", allowed: 1...8160)) {
            try Recipe(json: #"{"lengthInBytes":99999999999999999999}"#, type: .secret)
        }
    }

    @Test("keys must be 32 bytes")
    func keyLength() {
        for type in [DerivableType.symmetricKey, .unsealingKey, .signingKey] {
            #expect(throws: DerivationError.lengthMustBe32(type)) {
                try Recipe(json: #"{"lengthInBytes":16}"#, type: type)
            }
        }
    }

    @Test("password length resolves from bits or words, and bytes follow the words")
    func passwordLength() throws {
        #expect(try Recipe(json: #"{"lengthInBits":90}"#, type: .password).lengthInWords == 10)
        #expect(try Recipe(json: #"{"lengthInBits":1}"#, type: .password).lengthInWords == 1)
        #expect(try Recipe(json: #"{"lengthInBits":9180}"#, type: .password).lengthInWords == 1020)
        #expect(try Recipe(json: #"{"lengthInWords":3}"#, type: .password).lengthInBytes == 24)
        #expect(try Recipe(json: #"{"lengthInBits":90,"lengthInWords":10}"#, type: .password).lengthInWords == 10)
        #expect(try Recipe(json: #"{"lengthInBytes":16}"#, type: .password).lengthInBytes == 120)
        #expect(
            try Recipe(json: #"{"wordList":"EN_1024_words_6_chars_max_ed_4_20200917"}"#, type: .password).lengthInWords
                == 13)
        #expect(
            try Recipe(
                json: #"{"wordList":"EN_1024_words_6_chars_max_ed_4_20200917","lengthInBits":1}"#, type: .password
            ).lengthInWords == 1)
        #expect(
            try Recipe(
                json: #"{"wordList":"EN_1024_words_6_chars_max_ed_4_20200917","lengthInBits":10200}"#, type: .password
            ).lengthInWords == 1020)
        #expect(throws: DerivationError.bitsAndWordsConflict) {
            try Recipe(json: #"{"lengthInBits":1,"lengthInWords":9}"#, type: .password)
        }
        #expect(throws: DerivationError.outOfRange(field: "lengthInWords", allowed: 1...1020)) {
            try Recipe(json: #"{"lengthInWords":0}"#, type: .password)
        }
        #expect(throws: DerivationError.outOfRange(field: "lengthInWords", allowed: 1...1020)) {
            try Recipe(json: #"{"lengthInWords":1021}"#, type: .password)
        }
        #expect(throws: DerivationError.outOfRange(field: "lengthInBits", allowed: 1...9180)) {
            try Recipe(json: #"{"lengthInBits":0}"#, type: .password)
        }
        #expect(throws: DerivationError.outOfRange(field: "lengthInBits", allowed: 1...9180)) {
            try Recipe(json: #"{"lengthInBits":9181}"#, type: .password)
        }
        #expect(throws: DerivationError.outOfRange(field: "lengthInBits", allowed: 1...10200)) {
            try Recipe(
                json: #"{"wordList":"EN_1024_words_6_chars_max_ed_4_20200917","lengthInBits":10201}"#, type: .password)
        }
        #expect(throws: DerivationError.unknownWordList("nonsense")) {
            try Recipe(json: #"{"wordList":"nonsense"}"#, type: .password)
        }
    }

    @Test("lengthInChars is 1 or more")
    func lengthInChars() throws {
        #expect(try Recipe(json: #"{"lengthInChars":1}"#, type: .password).lengthInChars == 1)
        #expect(try Recipe(json: #"{"lengthInChars":64}"#, type: .password).lengthInChars == 64)
        #expect(throws: DerivationError.outOfRange(field: "lengthInChars", allowed: 1...Int.max)) {
            try Recipe(json: #"{"lengthInChars":0}"#, type: .password)
        }
        #expect(throws: DerivationError.outOfRange(field: "lengthInChars", allowed: 1...Int.max)) {
            try Recipe(json: #"{"lengthInChars":-1}"#, type: .password)
        }
    }

    @Test("password-only fields are salt on other types and are not validated there")
    func passwordFieldsElsewhere() throws {
        #expect(
            try Recipe(
                json: #"{"lengthInChars":0,"lengthInWords":0,"wordList":"nonsense","separator":"--"}"#, type: .secret
            )
            .lengthInBytes == 32)
    }

    @Test("malformed JSON is reported with the parser's reason")
    func malformed() {
        #expect(throws: DerivationError.recipeNotAnObject) { try Recipe(json: "[]", type: .secret) }
        #expect(throws: DerivationError.recipeNotAnObject) { try Recipe(json: " ", type: .secret) }
        #expect(throws: DerivationError.duplicateField("lengthInBytes")) {
            try Recipe(json: #"{"lengthInBytes":16,"lengthInBytes":8}"#, type: .secret)
        }
        #expect(throws: DerivationError.invalidJson("Not valid JSON near position 1")) {
            try Recipe(json: "{not json", type: .secret)
        }
    }

    @Test("every error has a message")
    func messages() {
        let errors: [DerivationError] = [
            .recipeNotAnObject, .invalidJson("x"), .duplicateField("a"), .wrongType(field: "a", expected: "an integer"),
            .outOfRange(field: "a", allowed: 1...2), .typeMismatch(recipe: "Secret", requested: .password),
            .invalidAlgorithm("x"),
            .unsupportedHashFunction("x"), .unknownWordList("x"), .lengthMustBe32(.signingKey), .bitsAndWordsConflict
        ]
        for error in errors {
            #expect(!(error.errorDescription ?? "").isEmpty)
        }
        #expect(
            DerivationError.unsupportedHashFunction("Argon2id").errorDescription
                == "The hash function Argon2id is not supported; only BLAKE2b is")
        #expect(
            DerivationError.outOfRange(field: "lengthInBytes", allowed: 1...8160).errorDescription
                == "lengthInBytes must be between 1 and 8160")
    }

    @Test("capitalize must be a JSON boolean and separator a string")
    func joiningFieldTypes() {
        #expect(throws: DerivationError.wrongType(field: "capitalize", expected: "true or false")) {
            try Recipe(json: #"{"separator":"-","capitalize":1}"#, type: .password)
        }
        #expect(throws: DerivationError.wrongType(field: "capitalize", expected: "true or false")) {
            try Recipe(json: #"{"separator":"-","capitalize":"yes"}"#, type: .password)
        }
        #expect(throws: DerivationError.wrongType(field: "separator", expected: "a string")) {
            try Recipe(json: #"{"separator":1}"#, type: .password)
        }
    }

    @Test("a password without separator is joined the reference way; with one, the modern way")
    func joining() throws {
        #expect(try Recipe(json: "{}", type: .password).joining == .reference)
        #expect(
            try Recipe(json: #"{"separator":"-"}"#, type: .password).joining
                == .modern(separator: .hyphen, capitalize: false))
        #expect(
            try Recipe(json: #"{"separator":"digits","capitalize":true}"#, type: .password).joining
                == .modern(separator: .digits, capitalize: true))
        for (text, separator) in [
            ("-", Separator.hyphen), (" ", .space), (".", .period), (",", .comma), ("_", .underscore), ("", .empty),
            ("digits", .digits)
        ] {
            #expect(
                try Recipe(json: #"{"separator":"\#(text)"}"#, type: .password).joining
                    == .modern(separator: separator, capitalize: false))
        }
        #expect(throws: DerivationError.unknownSeparator("--")) {
            try Recipe(json: #"{"separator":"--"}"#, type: .password)
        }
        #expect(throws: DerivationError.invalidJoining) {
            try Recipe(json: #"{"capitalize":true}"#, type: .password)
        }
        #expect(throws: DerivationError.invalidJoining) {
            try Recipe(json: #"{"capitalize":false}"#, type: .password)
        }
    }

    @Test("a character set joins one way and takes its length in characters")
    func characterSets() throws {
        let pin = try Recipe(json: #"{"wordList":"CHARS_10_digits_20261002","lengthInChars":6}"#, type: .password)
        #expect(pin.lengthInWords == 6)
        #expect(pin.lengthInBytes == 48)
        #expect(pin.lengthInChars == 6)
        #expect(pin.joining == .modern(separator: .empty, capitalize: false))
        let emoji = try Recipe(json: #"{"wordList":"EMOJI_512_single_code_point_20261002"}"#, type: .password)
        #expect(emoji.lengthInWords == 15)
        let words = try Recipe(
            json: #"{"wordList":"CHARS_67_letters_digits_symbols_20261002","lengthInWords":10,"lengthInChars":4}"#,
            type: .password)
        #expect(words.lengthInWords == 10)
        #expect(words.lengthInChars == 4)
        #expect(
            try Recipe(json: #"{"wordList":"CHARS_49_letters_20261002","lengthInChars":1020}"#, type: .password)
                .lengthInWords == 1020)
        #expect(throws: DerivationError.outOfRange(field: "lengthInChars", allowed: 1...1020)) {
            try Recipe(json: #"{"wordList":"CHARS_10_digits_20261002","lengthInChars":1021}"#, type: .password)
        }
        #expect(
            try Recipe(
                json: #"{"wordList":"CHARS_10_digits_20261002","separator":"","capitalize":false}"#, type: .password
            )
            .joining == .modern(separator: .empty, capitalize: false))
        #expect(throws: DerivationError.invalidJoining) {
            try Recipe(json: #"{"wordList":"CHARS_10_digits_20261002","separator":"-"}"#, type: .password)
        }
        #expect(throws: DerivationError.invalidJoining) {
            try Recipe(json: #"{"wordList":"EMOJI_512_single_code_point_20261002","capitalize":true}"#, type: .password)
        }
    }

    @Test("the EFF list rounds bits up to whole words")
    func effBits() throws {
        let eff = "EFF_large_7776_words_9_chars_max_20160719"
        #expect(try Recipe(json: #"{"wordList":"\#(eff)"}"#, type: .password).lengthInWords == 10)
        #expect(try Recipe(json: #"{"wordList":"\#(eff)","lengthInBits":12}"#, type: .password).lengthInWords == 1)
        #expect(try Recipe(json: #"{"wordList":"\#(eff)","lengthInBits":13}"#, type: .password).lengthInWords == 2)
        #expect(
            try Recipe(json: #"{"wordList":"\#(eff)","lengthInBits":128,"lengthInWords":10}"#, type: .password)
                .lengthInWords == 10)
        #expect(throws: DerivationError.bitsAndWordsConflict) {
            try Recipe(json: #"{"wordList":"\#(eff)","lengthInBits":128,"lengthInWords":11}"#, type: .password)
        }
    }

    @Test("joining fields are salt on every other type")
    func joiningElsewhere() throws {
        let recipe = try Recipe(json: #"{"separator":"--","capitalize":"yes"}"#, type: .secret)
        #expect(recipe.joining == .reference)
        #expect(recipe.lengthInBytes == 32)
    }
}
