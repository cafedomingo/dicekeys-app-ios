//
//  RecipeJsonTests.swift
//  DiceKeysTests
//

import Testing
import Derivation

@Suite("Recipe JSON canonical form")
struct RecipeJsonTests {
    @Test("fields sort with purpose first, # last, then UTF-16 code unit order")
    func objectOrder() {
        let object = RecipeJsonValue.object([
            RecipeJsonField(name: "#", value: .int(3)),
            RecipeJsonField(name: "b", value: .int(1)),
            RecipeJsonField(name: "purpose", value: .text("p")),
            RecipeJsonField(name: "B", value: .int(2)),
            RecipeJsonField(name: "a", value: .int(0))
        ])
        #expect(object.canonicalText == ##"{"purpose":"p","B":2,"a":0,"b":1,"#":3}"##)
    }

    @Test("duplicate names keep their original order")
    func duplicatesAreStable() {
        let object = RecipeJsonValue.object([
            RecipeJsonField(name: "b", value: .int(1)),
            RecipeJsonField(name: "a", value: .int(2)),
            RecipeJsonField(name: "a", value: .int(1))
        ])
        #expect(object.canonicalText == ##"{"a":2,"a":1,"b":1}"##)
    }

    @Test("nested objects and arrays use the same rule at every level")
    func nestedOrder() {
        let object = RecipeJsonValue.object([
            RecipeJsonField(name: "x", value: .object([
                RecipeJsonField(name: "z", value: .int(1)),
                RecipeJsonField(name: "purpose", value: .text("p")),
                RecipeJsonField(name: "#", value: .int(2))
            ])),
            RecipeJsonField(name: "list", value: .array([.bool(true), .null, .number(text: "1.50")]))
        ])
        #expect(object.canonicalText == ##"{"list":[true,null,1.50],"x":{"purpose":"p","z":1,"#":2}}"##)
    }

    @Test("strings built from Swift text are escaped like JSON.stringify")
    func stringEscaping() {
        #expect(RecipeJsonValue.text("say \"hi\" \\ tab\tend").canonicalText == #""say \"hi\" \\ tab\tend""#)
        #expect(RecipeJsonValue.text("\u{01}\u{08}\u{0C}\n\r").canonicalText == #""\u0001\b\f\n\r""#)
        #expect(RecipeJsonValue.text("café/😀").canonicalText == #""café/😀""#)
        #expect(RecipeJsonValue.text("a\u{7f}b").canonicalText == "\"a\u{7f}b\"")
    }

    @Test("canonically equivalent names still sort by their UTF-16 code units")
    func equivalentNamesSortByCodeUnits() {
        let object = RecipeJsonValue.object([
            RecipeJsonField(name: "\u{E9}", value: .int(1)),
            RecipeJsonField(name: "e\u{301}", value: .int(2))
        ])
        #expect(object.canonicalText == "{\"e\u{301}\":2,\"\u{E9}\":1}")
    }

    // From the reference's recipe-canonicalization.test.ts, plus the Android cases.
    static let referenceVectors: [(input: String, expected: String)] = [
        (##"{"#":3,"allow":[{"host":"*.example.com"}]}"##, ##"{"allow":[{"host":"*.example.com"}],"#":3}"##),
        (##"{"#":3,"allow":[{"host":"*.example.com"}],"purpose":"Life? Don't talk to me about life!" }"##,
         ##"{"purpose":"Life? Don't talk to me about life!","allow":[{"host":"*.example.com"}],"#":3}"##),
        (#"{"allow":[{"paths":["lo", "yo"],"host":"*.example.com"}]}"#, #"{"allow":[{"host":"*.example.com","paths":["lo","yo"]}]}"#),
        (" {  \"allow\" : [  {\"host\"\n:\"*.example.com\"}\t ]    }\n\n", #"{"allow":[{"host":"*.example.com"}]}"#),
        (##"{"allow":[{"paths":["lo", "yo"],"host":"*.example.com"}],"#":3, "purpose":"Don't know", "lengthInChars":3, "lengthInBytes": 15, "UNANTICIPATED_CAPITALIZED_FIELD":{}}"##,
         ##"{"purpose":"Don't know","UNANTICIPATED_CAPITALIZED_FIELD":{},"allow":[{"host":"*.example.com","paths":["lo","yo"]}],"lengthInBytes":15,"lengthInChars":3,"#":3}"##),
        (##"{"allow":[{"paths":["lo", "yo"],"host":"*.example.com"}],"#":3, "purpose":"Don't know", "lengthInChars":3, "lengthInBytes": 15, "UNANTICIPATED_CAPITALIZED_FIELD":[ ] }"##,
         ##"{"purpose":"Don't know","UNANTICIPATED_CAPITALIZED_FIELD":[],"allow":[{"host":"*.example.com","paths":["lo","yo"]}],"lengthInBytes":15,"lengthInChars":3,"#":3}"##),
        (#"{ "silly":[{"pointless":[ "spacing in", "out"]}]}"#, #"{"silly":[{"pointless":["spacing in","out"]}]}"#),
        (#"{ "silly":[{"pointless":[ "spacing in", "out"]}],   "crazy":3}"#, #"{"crazy":3,"silly":[{"pointless":["spacing in","out"]}]}"#)
    ]

    @Test("the reference test cases", arguments: referenceVectors)
    func referenceCases(vector: (input: String, expected: String)) throws {
        #expect(try vector.input.canonicalizedRecipe() == vector.expected)
    }

    // Each is a fixed point: numbers and strings are emitted exactly as written.
    static let preservedText: [String] = [
        #"{"a":1.50,"b":1e3,"c":-0,"d":0.30000000000000004,"e":12345678901234567890123}"#,
        #"{"a":true,"b":false,"c":null}"#,
        #"{"purpose":"a\/b\u007f\u001F\b\u00e9\ud83d\ude00"}"#,
        #"{"purpose":"say \"hi\""}"#,
        #"{"purpose":"back\\slash"}"#,
        #"{"purpose":"line\nbreak\ttab\u0001"}"#,
        #"{"purpose":"foo\",\"allow\":[{\"host\":\"attacker.example\"}]"}"#,
        #"{"purpose":"café 😀"}"#,
        #"{"":1}"#
    ]

    @Test("numbers, strings and escapes keep their source text", arguments: preservedText)
    func preservesSourceText(json: String) throws {
        #expect(try json.canonicalizedRecipe() == json)
    }

    static let duplicateKeys: [String] = [#"{"a":1,"a":2}"#, #"{"x":{"purpose":"a","purpose":"b"}}"#, #"{"a":1,"\u0061":2}"#]

    @Test("duplicate keys are rejected, at every level", arguments: duplicateKeys)
    func rejectsDuplicateKeys(json: String) {
        var thrown: RecipeJsonError?
        do { _ = try json.canonicalizedRecipe() } catch { thrown = error }
        guard case .duplicateKey = thrown else {
            Issue.record("expected .duplicateKey, got \(String(describing: thrown))")
            return
        }
    }

    @Test("keys sort by UTF-16 code unit, so an emoji sorts before U+FF5E and uppercase before lowercase")
    func keyOrderIsUTF16() throws {
        #expect(try #"{"～":1,"😀":2}"#.canonicalizedRecipe() == #"{"😀":2,"～":1}"#)
        #expect(try #"{"～":1,"\ud83d\ude00":2}"#.canonicalizedRecipe() == #"{"😀":2,"～":1}"#)
        #expect(try #"{"b":1,"B":2}"#.canonicalizedRecipe() == #"{"B":2,"b":1}"#)
        #expect(try ##"{"x":{"z":1,"purpose":"p","#":2}}"##.canonicalizedRecipe() == ##"{"x":{"purpose":"p","z":1,"#":2}}"##)
    }

    @Test("keys are written decoded, as the reference does")
    func keysAreWrittenDecoded() throws {
        #expect(try #"{"\u0070urpose":"x","a":1}"#.canonicalizedRecipe() == #"{"purpose":"x","a":1}"#)
        #expect(try #"{"a":1,"\u0070urpose":"x"}"#.canonicalizedRecipe() == #"{"purpose":"x","a":1}"#)
        #expect(try #"{"é":1,"e":2}"#.canonicalizedRecipe() == #"{"e":2,"é":1}"#)
    }

    static let unrepresentableKeys: [String] = [
        #"{"purpose":"x","we\"ird":1}"#, #"{"a\"b":1}"#, #"{"a\\b":1}"#, #"{"a\nb":1}"#, #"{"a\u0001b":1}"#
    ]

    @Test("keys the reference would write as invalid JSON are rejected", arguments: unrepresentableKeys)
    func rejectsUnrepresentableKeys(json: String) {
        var thrown: RecipeJsonError?
        do { _ = try json.canonicalizedRecipe() } catch { thrown = error }
        guard case .unrepresentableKey = thrown else {
            Issue.record("expected .unrepresentableKey, got \(String(describing: thrown))")
            return
        }
    }

    static let notObjects: [String] = ["", "   ", "[]", "\"x\"", "123", "null", "true"]

    @Test("anything but an object is rejected", arguments: notObjects)
    func rejectsNonObjects(json: String) {
        #expect(throws: RecipeJsonError.notAnObject) { try json.canonicalizedRecipe() }
    }

    static let invalid: [String] = [
        "{", #"{"a":1,}"#, #"{"a":01}"#, #"{"a":1.}"#, #"{"a":.5}"#, #"{"a":+1}"#, #"{"a":"\x"}"#,
        #"{"a":1}x"#, #"{"a" 1}"#, #"{a:1}"#, #"{"a":tru}"#, #"{"a":"unterminated}"#,
        "{\"a\":\"raw\nnewline\"}", #"{"a":"\u12"}"#, #"{"\ud83d":1}"#, #"{"a":[1,]}"#, #"{"a":1 "b":2}"#,
        #"{"\ude00":1}"#, #"{"\ud83dx":1}"#, #"{"\ud83d\ud83d":1}"#, #"{"\ud83dA":1}"#
    ]

    @Test("invalid JSON is rejected", arguments: invalid)
    func rejectsInvalidJson(json: String) {
        var thrown: RecipeJsonError?
        do { _ = try json.canonicalizedRecipe() } catch { thrown = error }
        guard case .invalid = thrown else {
            Issue.record("expected .invalid, got \(String(describing: thrown))")
            return
        }
    }

    @Test("nesting deeper than 128 levels is rejected, ordinary nesting is accepted")
    func nestingDepthIsCapped() throws {
        func nested(_ levels: Int) -> String {
            #"{"a":"# + String(repeating: "[", count: levels) + String(repeating: "]", count: levels) + "}"
        }
        #expect(try nested(100).canonicalizedRecipe() == nested(100))
        // The object is level 1, so 127 arrays is the deepest accepted.
        #expect(try nested(127).canonicalizedRecipe() == nested(127))
        for levels in [128, 129, 10_000] {
            #expect(throws: RecipeJsonError.invalid(offset: 5 + 127)) { try nested(levels).canonicalizedRecipe() }
        }
    }

    @Test("a top-level object with trailing whitespace or a BOM is accepted")
    func leadingAndTrailing() throws {
        #expect(try "\u{FEFF}{\"a\":1}".canonicalizedRecipe() == #"{"a":1}"#)
        #expect(try "{\"a\":1}\n".canonicalizedRecipe() == #"{"a":1}"#)
    }

    @Test("decoding a quoted string handles every escape and surrogate pairs")
    func decodeString() throws {
        #expect(try RecipeJsonParser.decodeString(quoted: #""a\"b\\c\/d\b\f\n\r\t\u00e9\ud83d\ude00""#) == "a\"b\\c/d\u{08}\u{0C}\n\r\té😀")
        #expect(throws: RecipeJsonError.self) { try RecipeJsonParser.decodeString(quoted: #""\ud83d""#) }
    }

    @Test("errors have a message a person can act on")
    func errorMessages() {
        #expect(RecipeJsonError.duplicateKey(name: "a", offset: 1).message == "Each field name may appear only once")
        #expect(RecipeJsonError.unrepresentableKey(offset: 1).message == "A field name cannot contain quotes, backslashes or control characters")
        #expect(RecipeJsonError.notAnObject.message == "A recipe must be a JSON object, such as {\"purpose\":\"example\"}")
        #expect(RecipeJsonError.invalid(offset: 7).message == "Not valid JSON near position 7")
    }
}
