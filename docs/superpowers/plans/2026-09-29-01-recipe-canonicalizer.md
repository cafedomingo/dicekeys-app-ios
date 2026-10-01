# Recipe Canonicalizer Implementation Plan (PR 1 of 6)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the app's `JSONSerialization`-based recipe canonicalizer with one that emits recipes exactly as the DiceKeys TypeScript reference does, and reject raw JSON that is not an object instead of passing it through.

**Architecture:** One small recursive-descent JSON parser over UTF-8 bytes produces a value tree that keeps the source text of every number and string. A canonical serializer writes that tree back with sorted keys and no whitespace. Every place the app builds or inspects a recipe goes through that tree; the dictionary-based helpers and `JSONSerialization` are deleted.

**Tech Stack:** Swift 6.2, Swift Testing, SwiftLint (strict), XcodeGen, xcodebuild on the iOS Simulator.

**Spec:** `docs/superpowers/specs/2026-09-29-derivation-rewrite-design.md`, sections "Canonicalizer (app)" and "PR sequence" item 1.

## Global Constraints

- iOS 26 / macOS 26 deployment, Swift tools 6.2, strict concurrency (the app target already builds with it).
- No new dependencies.
- American spelling in code, comments, commits and the PR. No em-dashes anywhere.
- Comments explain why something non-obvious is the way it is; never what changed or what was deleted.
- No test-only accessors or lint suppressions in product code.
- Commit messages: imperative subject, no attribution trailers of any kind.
- Every Xcode command needs `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`. Generate the project with `xcodegen generate` before building; `DiceKeys.xcodeproj` is not committed.
- Run the app tests as CI does: `xcodebuild test -project DiceKeys.xcodeproj -scheme DiceKeys -destination "platform=iOS Simulator,id=$UDID" CODE_SIGN_IDENTITY=- DEVELOPMENT_TEAM=` where `$UDID` is any available iPhone simulator from `xcrun simctl list devices available`. Filter to one suite with `-only-testing:DiceKeysTests/RecipeJsonTests`.
- Lint before every commit: `swiftlint lint --strict --quiet`.
- Work on branch `worktree-derivation-rewrite` in worktree `.claude/worktrees/derivation-rewrite` (it already holds the spec commit). Do not touch other worktrees.

## Review Focus

Inputs the spec implies but that need a pinned test, each added to the owning task below:

1. A recipe whose only content is whitespace, or the empty string, must be rejected by the raw JSON builder (a blank field already means "incomplete"; a field of spaces must not become `{}`). Task 4.
2. A string containing a raw control character (an actual newline inside quotes) is invalid JSON and must be rejected, not passed through. Task 2.
3. A `\u` escape that is a lone surrogate in an object key must be rejected rather than crash `String` construction. Task 2.
4. A saved recipe from an earlier version that is not valid JSON (the old canonicalizer passed such text through verbatim) must still load, display and derive; only the accessors return nil. Task 3.
5. The template rebuild must keep every template field other than `#`, `lengthInChars` and `lengthInBytes`, including nested `allow` objects, byte for byte. Task 3.

---

## File Structure

- Create `DiceKeys/Model/Recipes/RecipeJson.swift`: the value tree (`RecipeJsonValue`, `RecipeJsonField`), the parser (`RecipeJsonParser`), the error, the canonical serializer, and the JSON string quoting used when the app builds a recipe from its own fields.
- Delete `DiceKeys/Model/Recipes/CanonicalizeJsonRecipe.swift`.
- Modify `DiceKeys/Model/Recipes/DerivationRecipe.swift`: build recipes from `RecipeJsonValue`; accessors read the parsed tree; remove the `Dictionary` and `String` helpers.
- Modify `DiceKeys/Features/Recipes/CustomRecipeModel.swift:127-128`: the raw JSON path throws and reports.
- Create `Tests/DiceKeysTests/RecipeJsonTests.swift` (replaces `CanonicalizeRecipeJsonTests.swift`, which is deleted).
- Create `Tests/DiceKeysTests/RecipeBuildingTests.swift`: building from fields, template rebuild, accessors, the raw JSON builder path.

---

### Task 1: The value tree and the canonical serializer

**Files:**
- Create: `DiceKeys/Model/Recipes/RecipeJson.swift`
- Test: `Tests/DiceKeysTests/RecipeJsonTests.swift`

**Interfaces:**
- Produces:
  - `indirect enum RecipeJsonValue: Equatable { case object([RecipeJsonField]), array([RecipeJsonValue]), string(quoted: String), number(text: String), bool(Bool), null }`
  - `static func RecipeJsonValue.text(_ value: String) -> RecipeJsonValue` (escapes and quotes; named `text` because a static `string(_:)` would collide with the `string(quoted:)` case)
  - `static func RecipeJsonValue.int(_ value: Int) -> RecipeJsonValue`
  - `struct RecipeJsonField: Equatable { let name: String; let quotedName: String; let value: RecipeJsonValue; init(name: String, value: RecipeJsonValue) }`
  - `var RecipeJsonValue.canonicalText: String`
  - `func quotedJsonString(_ string: String) -> String` (kept from the old file, unchanged)

- [ ] **Step 1: Write the failing tests**

Create `Tests/DiceKeysTests/RecipeJsonTests.swift`:

```swift
//
//  RecipeJsonTests.swift
//  DiceKeysTests
//

import Testing
@testable import DiceKeys

@Suite("Recipe JSON canonical form")
struct RecipeJsonTests {
    @Test("fields sort with purpose first, # last, then UTF-16 code unit order")
    func objectOrder() {
        let object = RecipeJsonValue.object([
            RecipeJsonField(name: "#", value: .int(3)),
            RecipeJsonField(name: "b", value: .int(1)),
            RecipeJsonField(name: "purpose", value: .text("p")),
            RecipeJsonField(name: "B", value: .int(2)),
            RecipeJsonField(name: "a", value: .int(0)),
        ])
        #expect(object.canonicalText == #"{"purpose":"p","B":2,"a":0,"b":1,"#":3}"#)
    }

    @Test("duplicate names keep their original order")
    func duplicatesAreStable() {
        let object = RecipeJsonValue.object([
            RecipeJsonField(name: "b", value: .int(1)),
            RecipeJsonField(name: "a", value: .int(2)),
            RecipeJsonField(name: "a", value: .int(1)),
        ])
        #expect(object.canonicalText == #"{"a":2,"a":1,"b":1}"#)
    }

    @Test("nested objects and arrays use the same rule at every level")
    func nestedOrder() {
        let object = RecipeJsonValue.object([
            RecipeJsonField(name: "x", value: .object([
                RecipeJsonField(name: "z", value: .int(1)),
                RecipeJsonField(name: "purpose", value: .text("p")),
                RecipeJsonField(name: "#", value: .int(2)),
            ])),
            RecipeJsonField(name: "list", value: .array([.bool(true), .null, .number(text: "1.50")])),
        ])
        #expect(object.canonicalText == #"{"list":[true,null,1.50],"x":{"purpose":"p","z":1,"#":2}}"#)
    }

    @Test("strings built from Swift text are escaped like JSON.stringify")
    func stringEscaping() {
        #expect(RecipeJsonValue.text("say \"hi\" \\ tab\tend").canonicalText == #""say \"hi\" \\ tab\tend""#)
        #expect(RecipeJsonValue.text("\u{01}\u{08}\u{0C}\n\r").canonicalText == #""\u0001\b\f\n\r""#)
        #expect(RecipeJsonValue.text("café/😀").canonicalText == #""café/😀""#)
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run:
```bash
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
xcodegen generate --quiet
UDID=$(xcrun simctl list devices available -j | python3 -c 'import json,sys; d=json.load(sys.stdin)["devices"]; print(next(x["udid"] for r in sorted(d, reverse=True) for x in d[r] if x["isAvailable"] and x["name"].startswith("iPhone")))')
xcodebuild test -project DiceKeys.xcodeproj -scheme DiceKeys -destination "platform=iOS Simulator,id=$UDID" CODE_SIGN_IDENTITY=- DEVELOPMENT_TEAM= -only-testing:DiceKeysTests/RecipeJsonTests 2>&1 | grep -E 'error:|Test Suite|passed|failed'
```
Expected: compile errors, `RecipeJsonValue` not found.

- [ ] **Step 3: Write the value tree, serializer and quoting**

Create `DiceKeys/Model/Recipes/RecipeJson.swift`:

```swift
//
//  RecipeJson.swift
//  DiceKeys
//
//  A recipe is hashed as text, so the canonical form must be reproducible character for
//  character across every DiceKeys app. This follows the reference implementation in
//  https://github.com/dicekeys/dicekeys-app-typescript/blob/main/web/src/dicekeys/canonicalizeRecipeJson.ts:
//  numbers and strings keep their source text, whitespace goes, and object fields sort by
//  UTF-16 code unit with "purpose" first and "#" last, at every level.
//

import Foundation

/// A JSON value that keeps the source text of numbers and strings.
indirect enum RecipeJsonValue: Equatable {
    case object([RecipeJsonField])
    case array([RecipeJsonValue])
    /// The original quoted text, quotes and escapes included.
    case string(quoted: String)
    /// The original sign, digits, fraction and exponent.
    case number(text: String)
    case bool(Bool)
    case null

    static func text(_ value: String) -> RecipeJsonValue {
        .string(quoted: quotedJsonString(value))
    }

    static func int(_ value: Int) -> RecipeJsonValue {
        .number(text: String(value))
    }

    /// The reference canonical form: no whitespace, fields sorted, source text preserved.
    var canonicalText: String {
        switch self {
        case .object(let fields):
            let sorted = fields.enumerated().sorted { lhs, rhs in
                if RecipeJsonField.precedes(lhs.element.name, rhs.element.name) { return true }
                if RecipeJsonField.precedes(rhs.element.name, lhs.element.name) { return false }
                return lhs.offset < rhs.offset
            }
            return "{" + sorted.map { "\($0.element.quotedName):\($0.element.value.canonicalText)" }.joined(separator: ",") + "}"
        case .array(let items):
            return "[" + items.map(\.canonicalText).joined(separator: ",") + "]"
        case .string(let quoted):
            return quoted
        case .number(let text):
            return text
        case .bool(let value):
            return value ? "true" : "false"
        case .null:
            return "null"
        }
    }
}

struct RecipeJsonField: Equatable {
    /// The decoded name, used for ordering and lookup.
    let name: String
    /// The original quoted text, written back as is.
    let quotedName: String
    let value: RecipeJsonValue

    init(name: String, quotedName: String, value: RecipeJsonValue) {
        self.name = name
        self.quotedName = quotedName
        self.value = value
    }

    init(name: String, value: RecipeJsonValue) {
        self.init(name: name, quotedName: quotedJsonString(name), value: value)
    }

    /// "#" (the sequence number) always comes last and "purpose" always first; the rest sort
    /// by UTF-16 code unit, which is what JavaScript's `<` on strings compares.
    static func precedes(_ lhs: String, _ rhs: String) -> Bool {
        if lhs == rhs { return false }
        if lhs == "#" { return false }
        if rhs == "#" { return true }
        if lhs == "purpose" { return true }
        if rhs == "purpose" { return false }
        return lhs.utf16.lexicographicallyPrecedes(rhs.utf16)
    }
}

/// Quotes a string for JSON output the way `JSON.stringify` does: quotes, backslashes and
/// control characters escaped, everything else written raw.
func quotedJsonString(_ string: String) -> String {
    var quoted = "\""
    for scalar in string.unicodeScalars {
        switch scalar {
        case "\"": quoted += "\\\""
        case "\\": quoted += "\\\\"
        case "\n": quoted += "\\n"
        case "\r": quoted += "\\r"
        case "\t": quoted += "\\t"
        case "\u{08}": quoted += "\\b"
        case "\u{0C}": quoted += "\\f"
        case _ where scalar.value < 0x20: quoted += String(format: "\\u%04x", scalar.value)
        default: quoted.unicodeScalars.append(scalar)
        }
    }
    return quoted + "\""
}
```

- [ ] **Step 4: Define `quotedJsonString` once**

`quotedJsonString` now lives in `RecipeJson.swift`, so remove it from `DiceKeys/Model/Recipes/CanonicalizeJsonRecipe.swift` (its doc comment and the function, lines 67-86). Leave that file's `compareObjectFieldNames` and `toCanonicalizeRecipeJson` in place; Task 3 deletes the file once nothing calls them.

- [ ] **Step 5: Run the tests to verify they pass**

Same command as Step 2. Expected: `RecipeJsonTests` 4 tests pass. Also run `swiftlint lint --strict --quiet` and expect no output.

- [ ] **Step 6: Commit**

```bash
git add DiceKeys/Model/Recipes/RecipeJson.swift DiceKeys/Model/Recipes/CanonicalizeJsonRecipe.swift Tests/DiceKeysTests/RecipeJsonTests.swift
git commit -m "Add a recipe JSON value tree with the reference canonical form"
```

---

### Task 2: The parser

**Files:**
- Modify: `DiceKeys/Model/Recipes/RecipeJson.swift`
- Test: `Tests/DiceKeysTests/RecipeJsonTests.swift`

**Interfaces:**
- Produces:
  - `enum RecipeJsonError: Error, Equatable { case notAnObject; case invalid(offset: Int) }` with `var message: String`
  - `struct RecipeJsonParser { static func parseObject(_ text: String) throws(RecipeJsonError) -> [RecipeJsonField]; static func decodeString(quoted: String) throws(RecipeJsonError) -> String }`
  - `extension String { func canonicalizedRecipe() throws(RecipeJsonError) -> String }`

- [ ] **Step 1: Write the failing tests**

Append to the suite in `Tests/DiceKeysTests/RecipeJsonTests.swift` (inside `struct RecipeJsonTests`):

```swift
    // The reference's own test cases, from
    // dicekeys-app-typescript/web/src/tests/recipe-canonicalization.test.ts, plus the Android
    // ones this app already carried. Both apps agree on all of these.
    static let referenceVectors: [(input: String, expected: String)] = [
        (#"{"#":3,"allow":[{"host":"*.example.com"}]}"#, #"{"allow":[{"host":"*.example.com"}],"#":3}"#),
        (#"{"#":3,"allow":[{"host":"*.example.com"}],"purpose":"Life? Don't talk to me about life!" }"#,
         #"{"purpose":"Life? Don't talk to me about life!","allow":[{"host":"*.example.com"}],"#":3}"#),
        (#"{"allow":[{"paths":["lo", "yo"],"host":"*.example.com"}]}"#, #"{"allow":[{"host":"*.example.com","paths":["lo","yo"]}]}"#),
        (" {  \"allow\" : [  {\"host\"\n:\"*.example.com\"}\t ]    }\n\n", #"{"allow":[{"host":"*.example.com"}]}"#),
        (#"{"allow":[{"paths":["lo", "yo"],"host":"*.example.com"}],"#":3, "purpose":"Don't know", "lengthInChars":3, "lengthInBytes": 15, "UNANTICIPATED_CAPITALIZED_FIELD":{}}"#,
         #"{"purpose":"Don't know","UNANTICIPATED_CAPITALIZED_FIELD":{},"allow":[{"host":"*.example.com","paths":["lo","yo"]}],"lengthInBytes":15,"lengthInChars":3,"#":3}"#),
        (#"{"allow":[{"paths":["lo", "yo"],"host":"*.example.com"}],"#":3, "purpose":"Don't know", "lengthInChars":3, "lengthInBytes": 15, "UNANTICIPATED_CAPITALIZED_FIELD":[ ] }"#,
         #"{"purpose":"Don't know","UNANTICIPATED_CAPITALIZED_FIELD":[],"allow":[{"host":"*.example.com","paths":["lo","yo"]}],"lengthInBytes":15,"lengthInChars":3,"#":3}"#),
        (#"{ "silly":[{"pointless":[ "spacing in", "out"]}]}"#, #"{"silly":[{"pointless":["spacing in","out"]}]}"#),
        (#"{ "silly":[{"pointless":[ "spacing in", "out"]}],   "crazy":3}"#, #"{"crazy":3,"silly":[{"pointless":["spacing in","out"]}]}"#),
    ]

    @Test("the reference test cases", arguments: referenceVectors)
    func referenceCases(vector: (input: String, expected: String)) throws {
        #expect(try vector.input.canonicalizedRecipe() == vector.expected)
    }

    // Source text the old JSONSerialization-based canonicalizer rewrote. Each of these is a
    // fixed point: the reference emits numbers and strings exactly as written.
    static let preservedText: [String] = [
        #"{"a":1.50,"b":1e3,"c":-0,"d":0.30000000000000004,"e":12345678901234567890123}"#,
        #"{"a":true,"b":false,"c":null}"#,
        #"{"purpose":"a\/b\u007f\u001F\b\u00e9\ud83d\ude00"}"#,
        #"{"purpose":"say \"hi\""}"#,
        #"{"purpose":"back\\slash"}"#,
        #"{"purpose":"line\nbreak\ttab\u0001"}"#,
        #"{"purpose":"foo\",\"allow\":[{\"host\":\"attacker.example\"}]"}"#,
        #"{"purpose":"x","we\"ird":1}"#,
        #"{"purpose":"café 😀"}"#,
        #"{"":1}"#,
    ]

    @Test("numbers, strings and escapes keep their source text", arguments: preservedText)
    func preservesSourceText(json: String) throws {
        #expect(try json.canonicalizedRecipe() == json)
    }

    @Test("duplicate keys are kept in order")
    func duplicateKeys() throws {
        #expect(try #"{"a":1,"a":2}"#.canonicalizedRecipe() == #"{"a":1,"a":2}"#)
        #expect(try #"{"b":1,"a":2,"a":1}"#.canonicalizedRecipe() == #"{"a":2,"a":1,"b":1}"#)
    }

    @Test("keys sort by UTF-16 code unit, so an emoji sorts before U+FF5E and uppercase before lowercase")
    func keyOrderIsUTF16() throws {
        #expect(try #"{"～":1,"😀":2}"#.canonicalizedRecipe() == #"{"😀":2,"～":1}"#)
        #expect(try #"{"～":1,"\ud83d\ude00":2}"#.canonicalizedRecipe() == #"{"\ud83d\ude00":2,"～":1}"#)
        #expect(try #"{"b":1,"B":2}"#.canonicalizedRecipe() == #"{"B":2,"b":1}"#)
        #expect(try #"{"x":{"z":1,"purpose":"p","#":2}}"#.canonicalizedRecipe() == #"{"x":{"purpose":"p","z":1,"#":2}}"#)
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
        #expect(RecipeJsonError.notAnObject.message == "A recipe must be a JSON object, such as {\"purpose\":\"example\"}")
        #expect(RecipeJsonError.invalid(offset: 7).message == "Not valid JSON near position 7")
    }
```

- [ ] **Step 2: Run the tests to verify they fail**

Same command as Task 1 Step 2. Expected: compile errors, `canonicalizedRecipe` and `RecipeJsonParser` not found.

- [ ] **Step 3: Write the parser**

Append to `DiceKeys/Model/Recipes/RecipeJson.swift`:

```swift
enum RecipeJsonError: Error, Equatable {
    case notAnObject
    /// Byte offset into the UTF-8 text where parsing stopped.
    case invalid(offset: Int)

    var message: String {
        switch self {
        case .notAnObject: return "A recipe must be a JSON object, such as {\"purpose\":\"example\"}"
        case .invalid(let offset): return "Not valid JSON near position \(offset)"
        }
    }
}

/// A strict RFC 8259 parser that records where each number and string came from instead of
/// converting it, because the recipe's exact text is what gets hashed.
struct RecipeJsonParser {
    private let bytes: [UInt8]
    private var index = 0

    private init(_ text: String) {
        bytes = Array(text.utf8)
    }

    /// Parses a whole document that must be a single object. A leading byte order mark is
    /// tolerated because pasted text often carries one.
    static func parseObject(_ text: String) throws(RecipeJsonError) -> [RecipeJsonField] {
        var parser = RecipeJsonParser(text)
        if parser.bytes.starts(with: [0xEF, 0xBB, 0xBF]) { parser.index = 3 }
        parser.skipWhitespace()
        guard parser.peek == UInt8(ascii: "{") else {
            // Nothing at all, or valid JSON of another kind, is "not an object"; anything
            // else is invalid JSON, reported where it went wrong.
            if parser.peek == nil { throw .notAnObject }
            let other = try? parser.parseValue()
            parser.skipWhitespace()
            if other != nil, parser.index == parser.bytes.count { throw .notAnObject }
            throw .invalid(offset: parser.index)
        }
        let value = try parser.parseValue()
        parser.skipWhitespace()
        guard parser.index == parser.bytes.count else { throw .invalid(offset: parser.index) }
        guard case .object(let fields) = value else { throw .notAnObject }
        return fields
    }

    /// Decodes a quoted JSON string, escapes included, to the text it denotes.
    static func decodeString(quoted: String) throws(RecipeJsonError) -> String {
        var parser = RecipeJsonParser(quoted)
        guard parser.peek == UInt8(ascii: "\"") else { throw .invalid(offset: 0) }
        let value = try parser.parseString()
        guard parser.index == parser.bytes.count, case .string = value else { throw .invalid(offset: parser.index) }
        return try parser.decode(quotedRange: 0..<parser.bytes.count)
    }

    private var peek: UInt8? { index < bytes.count ? bytes[index] : nil }

    private mutating func skipWhitespace() {
        while let byte = peek, byte == 0x20 || byte == 0x09 || byte == 0x0A || byte == 0x0D { index += 1 }
    }

    private mutating func expect(_ literal: String) throws(RecipeJsonError) {
        let expected = Array(literal.utf8)
        guard bytes[index...].starts(with: expected) else { throw .invalid(offset: index) }
        index += expected.count
    }

    private mutating func parseValue() throws(RecipeJsonError) -> RecipeJsonValue {
        guard let byte = peek else { throw .invalid(offset: index) }
        switch byte {
        case UInt8(ascii: "{"): return try parseObjectBody()
        case UInt8(ascii: "["): return try parseArray()
        case UInt8(ascii: "\""): return try parseString()
        case UInt8(ascii: "t"): try expect("true"); return .bool(true)
        case UInt8(ascii: "f"): try expect("false"); return .bool(false)
        case UInt8(ascii: "n"): try expect("null"); return .null
        case UInt8(ascii: "-"), UInt8(ascii: "0")...UInt8(ascii: "9"): return try parseNumber()
        default: throw .invalid(offset: index)
        }
    }

    private mutating func parseObjectBody() throws(RecipeJsonError) -> RecipeJsonValue {
        index += 1
        var fields: [RecipeJsonField] = []
        skipWhitespace()
        if peek == UInt8(ascii: "}") { index += 1; return .object(fields) }
        while true {
            skipWhitespace()
            guard peek == UInt8(ascii: "\"") else { throw .invalid(offset: index) }
            let nameStart = index
            guard case .string(let quotedName) = try parseString() else { throw .invalid(offset: nameStart) }
            let name = try decode(quotedRange: nameStart..<index)
            skipWhitespace()
            guard peek == UInt8(ascii: ":") else { throw .invalid(offset: index) }
            index += 1
            skipWhitespace()
            let value = try parseValue()
            fields.append(RecipeJsonField(name: name, quotedName: quotedName, value: value))
            skipWhitespace()
            switch peek {
            case UInt8(ascii: ","): index += 1
            case UInt8(ascii: "}"): index += 1; return .object(fields)
            default: throw .invalid(offset: index)
            }
        }
    }

    private mutating func parseArray() throws(RecipeJsonError) -> RecipeJsonValue {
        index += 1
        var items: [RecipeJsonValue] = []
        skipWhitespace()
        if peek == UInt8(ascii: "]") { index += 1; return .array(items) }
        while true {
            skipWhitespace()
            items.append(try parseValue())
            skipWhitespace()
            switch peek {
            case UInt8(ascii: ","): index += 1
            case UInt8(ascii: "]"): index += 1; return .array(items)
            default: throw .invalid(offset: index)
            }
        }
    }

    /// Scans a string, validating escapes, and returns its source text with the quotes.
    private mutating func parseString() throws(RecipeJsonError) -> RecipeJsonValue {
        let start = index
        index += 1
        while true {
            guard let byte = peek else { throw .invalid(offset: index) }
            switch byte {
            case UInt8(ascii: "\""):
                index += 1
                return .string(quoted: String(decoding: bytes[start..<index], as: UTF8.self))
            case UInt8(ascii: "\\"):
                index += 1
                guard let escaped = peek else { throw .invalid(offset: index) }
                switch escaped {
                case UInt8(ascii: "\""), UInt8(ascii: "\\"), UInt8(ascii: "/"), UInt8(ascii: "b"),
                     UInt8(ascii: "f"), UInt8(ascii: "n"), UInt8(ascii: "r"), UInt8(ascii: "t"):
                    index += 1
                case UInt8(ascii: "u"):
                    index += 1
                    _ = try parseHex4()
                default:
                    throw .invalid(offset: index)
                }
            case 0x00..<0x20:
                throw .invalid(offset: index)
            default:
                index += 1
            }
        }
    }

    private mutating func parseHex4() throws(RecipeJsonError) -> UInt32 {
        var value: UInt32 = 0
        for _ in 0..<4 {
            guard let byte = peek, let digit = Character(UnicodeScalar(byte)).hexDigitValue else { throw .invalid(offset: index) }
            value = value << 4 | UInt32(digit)
            index += 1
        }
        return value
    }

    private mutating func parseNumber() throws(RecipeJsonError) -> RecipeJsonValue {
        let start = index
        if peek == UInt8(ascii: "-") { index += 1 }
        guard let first = peek, first.isDigit else { throw .invalid(offset: index) }
        if first == UInt8(ascii: "0") { index += 1 } else { skipDigits() }
        if peek == UInt8(ascii: ".") {
            index += 1
            guard let byte = peek, byte.isDigit else { throw .invalid(offset: index) }
            skipDigits()
        }
        if peek == UInt8(ascii: "e") || peek == UInt8(ascii: "E") {
            index += 1
            if peek == UInt8(ascii: "+") || peek == UInt8(ascii: "-") { index += 1 }
            guard let byte = peek, byte.isDigit else { throw .invalid(offset: index) }
            skipDigits()
        }
        return .number(text: String(decoding: bytes[start..<index], as: UTF8.self))
    }

    private mutating func skipDigits() {
        while let byte = peek, byte.isDigit { index += 1 }
    }

    /// Decodes the escapes of an already validated quoted string in `bytes`.
    private func decode(quotedRange: Range<Int>) throws(RecipeJsonError) -> String {
        var scalars = String.UnicodeScalarView()
        var cursor = quotedRange.lowerBound + 1
        let end = quotedRange.upperBound - 1
        var pendingHighSurrogate: (value: UInt32, offset: Int)?
        func flushSurrogate() throws(RecipeJsonError) {
            if let pending = pendingHighSurrogate { throw .invalid(offset: pending.offset) }
        }
        while cursor < end {
            let byte = bytes[cursor]
            if byte != UInt8(ascii: "\\") {
                try flushSurrogate()
                // Copy one whole UTF-8 sequence.
                let length = byte < 0x80 ? 1 : byte < 0xE0 ? 2 : byte < 0xF0 ? 3 : 4
                let text = String(decoding: bytes[cursor..<cursor + length], as: UTF8.self)
                scalars.append(contentsOf: text.unicodeScalars)
                cursor += length
                continue
            }
            let escaped = bytes[cursor + 1]
            cursor += 2
            if escaped == UInt8(ascii: "u") {
                var copy = self
                copy.index = cursor
                let unit = try copy.parseHex4()
                cursor += 4
                if (0xD800...0xDBFF).contains(unit) {
                    try flushSurrogate()
                    pendingHighSurrogate = (unit, cursor - 6)
                    continue
                }
                if (0xDC00...0xDFFF).contains(unit) {
                    guard let high = pendingHighSurrogate else { throw .invalid(offset: cursor - 6) }
                    pendingHighSurrogate = nil
                    let combined = 0x10000 + ((high.value - 0xD800) << 10) + (unit - 0xDC00)
                    scalars.append(UnicodeScalar(combined)!)
                    continue
                }
                try flushSurrogate()
                scalars.append(UnicodeScalar(unit)!)
                continue
            }
            try flushSurrogate()
            switch escaped {
            case UInt8(ascii: "b"): scalars.append("\u{08}")
            case UInt8(ascii: "f"): scalars.append("\u{0C}")
            case UInt8(ascii: "n"): scalars.append("\n")
            case UInt8(ascii: "r"): scalars.append("\r")
            case UInt8(ascii: "t"): scalars.append("\t")
            default: scalars.append(UnicodeScalar(escaped))
            }
        }
        try flushSurrogate()
        return String(scalars)
    }
}

private extension UInt8 {
    var isDigit: Bool { self >= UInt8(ascii: "0") && self <= UInt8(ascii: "9") }
}

extension String {
    /// The recipe as the reference canonicalizer writes it.
    func canonicalizedRecipe() throws(RecipeJsonError) -> String {
        RecipeJsonValue.object(try RecipeJsonParser.parseObject(self)).canonicalText
    }
}
```

Two details to get right when implementing:
- `UnicodeScalar(combined)!` and `UnicodeScalar(unit)!` are safe: a combined pair is always a valid scalar, and a non-surrogate 16-bit unit is always a valid scalar. Keep the force unwraps; SwiftLint's `force_unwrapping` rule is not enabled.
- In `parseObject`, the guard branch for non-`{` input distinguishes "valid JSON but not an object" (`.notAnObject`) from garbage (`.invalid`). `""` and `"   "` are `.notAnObject`, which the raw JSON builder never reaches because a blank field means incomplete (Task 4 covers a field of spaces).

- [ ] **Step 4: Run the tests to verify they pass**

Same command as Task 1 Step 2. Expected: every `RecipeJsonTests` test passes. Run `swiftlint lint --strict --quiet` and expect no output.

- [ ] **Step 5: Commit**

```bash
git add DiceKeys/Model/Recipes/RecipeJson.swift Tests/DiceKeysTests/RecipeJsonTests.swift
git commit -m "Parse recipe JSON strictly, keeping the source text of numbers and strings"
```

---

### Task 3: Build and inspect recipes through the tree

**Files:**
- Modify: `DiceKeys/Model/Recipes/DerivationRecipe.swift:1-88` (helpers) and `:105-122, 164-192` (rebuild and accessors)
- Delete: `DiceKeys/Model/Recipes/CanonicalizeJsonRecipe.swift`
- Delete: `Tests/DiceKeysTests/CanonicalizeRecipeJsonTests.swift`
- Test: `Tests/DiceKeysTests/RecipeBuildingTests.swift`

**Interfaces:**
- Consumes: `RecipeJsonValue`, `RecipeJsonField`, `RecipeJsonParser.parseObject`, `RecipeJsonParser.decodeString`
- Produces (unchanged signatures, new bodies): `getRecipeJson(hosts:sequenceNumber:lengthInChars:lengthInBytes:)`, `getRecipeJson(purpose:sequenceNumber:lengthInChars:lengthInBytes:)`, `DerivationRecipe.init(template:sequenceNumber:lengthInChars:lengthInBytes:)`, `DerivationRecipe.purpose()`, `.lengthInChars()`, `.lengthInBytes()`; new `DerivationRecipe.fields: [RecipeJsonField]`

- [ ] **Step 1: Write the failing tests**

Create `Tests/DiceKeysTests/RecipeBuildingTests.swift`:

```swift
//
//  RecipeBuildingTests.swift
//  DiceKeysTests
//

import Testing
@testable import DiceKeys

@Suite("Building recipes from the app's fields")
struct RecipeBuildingTests {
    @Test("a purpose recipe escapes the purpose and orders the optional fields")
    func purposeRecipe() {
        #expect(getRecipeJson(purpose: #"say "hi""#) == #"{"purpose":"say \"hi\""}"#)
        #expect(getRecipeJson(purpose: "x", sequenceNumber: 2, lengthInChars: 20) == #"{"purpose":"x","lengthInChars":20,"#":2}"#)
        #expect(getRecipeJson(purpose: "x", sequenceNumber: 1, lengthInChars: 0, lengthInBytes: 64) == #"{"purpose":"x","lengthInBytes":64}"#)
    }

    @Test("a hosts recipe sorts the hosts")
    func hostsRecipe() {
        #expect(getRecipeJson(hosts: ["b.example", "a.example"]) == #"{"allow":["a.example","b.example"]}"#)
    }

    @Test("rebuilding from a template keeps every other field, nested objects included")
    func templateRebuild() {
        let apple = derivationRecipeTemplates.first { $0.name == "Apple" }!
        let rebuilt = DerivationRecipe(template: apple, sequenceNumber: 3, lengthInChars: 20)
        #expect(rebuilt.recipe == #"{"allow":[{"host":"*.apple.com"},{"host":"*.icloud.com"}],"lengthInChars":20,"#":3}"#)
        #expect(rebuilt.name == "Apple Password (3)")
        let unchanged = DerivationRecipe(template: apple, sequenceNumber: 1, lengthInChars: apple.lengthInChars())
        #expect(unchanged.recipe == apple.recipe)
    }

    @Test("every template is already in canonical form and parses")
    func templatesAreCanonical() throws {
        for template in derivationRecipeTemplates {
            #expect(try template.recipe.canonicalizedRecipe() == template.recipe)
        }
    }

    @Test("accessors read the parsed recipe and return nil for anything but the expected type")
    func accessors() {
        let recipe = DerivationRecipe(type: .Password, name: "n", recipe: #"{"purpose":"caf\u00e9","lengthInChars":32,"lengthInBytes":32.5}"#)
        #expect(recipe.purpose() == "café")
        #expect(recipe.lengthInChars() == 32)
        #expect(recipe.lengthInBytes() == nil)
        let odd = DerivationRecipe(type: .Password, name: "n", recipe: #"{"purpose":1,"lengthInChars":true}"#)
        #expect(odd.purpose() == nil)
        #expect(odd.lengthInChars() == nil)
    }

    @Test("a stored recipe that is not JSON still loads; only the accessors are empty")
    func storedGarbageStillLoads() {
        let stored = DerivationRecipe(type: .Password, name: "old", recipe: "{not json")
        #expect(stored.recipe == "{not json")
        #expect(stored.purpose() == nil)
        #expect(stored.fields.isEmpty)
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Same command as Task 1 Step 2 with `-only-testing:DiceKeysTests/RecipeBuildingTests`. Expected: `fields` not found, and `accessors` fails on `lengthInBytes` (the old code returns `nil` for `32.5` too, but `purpose` for `"caf\u00e9"` passes already; the compile error is what fails the run).

- [ ] **Step 3: Rewrite the helpers and accessors**

Replace lines 1-88 of `DiceKeys/Model/Recipes/DerivationRecipe.swift` (everything before `struct DerivationRecipe`) with:

```swift
//
//  Derivables.swift
//  DiceKeys
//
//  Created by Stuart Schechter on 2020/12/03.
//

import Foundation
import SeededCrypto

func getRecipeJson(hosts: [String], sequenceNumber: Int = 1, lengthInChars: Int = -1, lengthInBytes: Int = -1) -> String {
    RecipeJsonValue.object(
        [RecipeJsonField(name: "allow", value: .array(hosts.sorted().map { .text($0) }))]
        + optionalRecipeFields(sequenceNumber: sequenceNumber, lengthInChars: lengthInChars, lengthInBytes: lengthInBytes)
    ).canonicalText
}

func getRecipeJson(purpose: String, sequenceNumber: Int = 1, lengthInChars: Int = -1, lengthInBytes: Int = -1) -> String {
    RecipeJsonValue.object(
        [RecipeJsonField(name: "purpose", value: .text(purpose))]
        + optionalRecipeFields(sequenceNumber: sequenceNumber, lengthInChars: lengthInChars, lengthInBytes: lengthInBytes)
    ).canonicalText
}

/// The fields a user can set on any recipe. Each is written only when it differs from the
/// default, because a recipe with `"#":1` derives a different secret from one without it.
private func optionalRecipeFields(sequenceNumber: Int, lengthInChars: Int?, lengthInBytes: Int?) -> [RecipeJsonField] {
    var fields: [RecipeJsonField] = []
    if let lengthInChars, lengthInChars > 1 {
        fields.append(RecipeJsonField(name: "lengthInChars", value: .int(lengthInChars)))
    }
    if let lengthInBytes, lengthInBytes > 1 {
        fields.append(RecipeJsonField(name: "lengthInBytes", value: .int(lengthInBytes)))
    }
    if sequenceNumber > 1 {
        fields.append(RecipeJsonField(name: "#", value: .int(sequenceNumber)))
    }
    return fields
}

```

Then replace the body of `init(template:sequenceNumber:lengthInChars:lengthInBytes:)` (the lines from `var updateJsonObject` through the `self.recipe =` line) with:

```swift
        let kept = template.fields.filter { !DerivationRecipe.rebuildSkipJsonProperties.contains($0.name) }
        let added = optionalRecipeFields(
            sequenceNumber: sequenceNumber,
            lengthInChars: template.type == .Password ? lengthInChars : nil,
            lengthInBytes: template.type == .Secret ? lengthInBytes : nil
        )
        self.recipe = RecipeJsonValue.object(kept + added).canonicalText
```

`optionalRecipeFields` is `private` at file scope, so it is visible inside `DerivationRecipe` in the same file.

Then replace the three accessor functions `purpose()`, `lengthInChars()` and `lengthInBytes()` at the end of the file with:

```swift
    /// The recipe's fields, or none when the stored text is not a JSON object. Recipes saved
    /// by earlier versions were not validated, so this never throws.
    var fields: [RecipeJsonField] {
        (try? RecipeJsonParser.parseObject(recipe)) ?? []
    }

    func purpose() -> String? {
        guard case .string(let quoted) = fields.first(where: { $0.name == "purpose" })?.value else { return nil }
        return try? RecipeJsonParser.decodeString(quoted: quoted)
    }

    func lengthInChars() -> Int? {
        integerField("lengthInChars")
    }

    func lengthInBytes() -> Int? {
        integerField("lengthInBytes")
    }

    private func integerField(_ name: String) -> Int? {
        guard case .number(let text) = fields.first(where: { $0.name == name })?.value else { return nil }
        return Int(text)
    }
```

Delete `DiceKeys/Model/Recipes/CanonicalizeJsonRecipe.swift` and `Tests/DiceKeysTests/CanonicalizeRecipeJsonTests.swift` (its cases now live in `RecipeJsonTests.referenceVectors`).

`CustomRecipeModel.swift:128` still calls `rawJsonString.canonicalizeRecipeJson()`, which no longer exists; Task 4 replaces it. To keep this task's build green, make that one line `recipe = (try? rawJsonString.canonicalizedRecipe()) ?? rawJsonString` for now; Task 4 turns it into the reported error.

- [ ] **Step 4: Run the tests to verify they pass**

Run the whole `DiceKeysTests` target (drop `-only-testing`). Expected: `RecipeBuildingTests`, `RecipeJsonTests`, `DefaultOutputFormatTests` and `PasswordDerivationTests` pass; no other suite changes. Run `swiftlint lint --strict --quiet` and expect no output. Then run the unused-code check the way CI does, since two functions were deleted:

```bash
xcodebuild build -project DiceKeys.xcodeproj -scheme DiceKeys -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO DEVELOPMENT_TEAM= > build-ios.log 2>&1
swiftlint analyze --strict --config .swiftlint.yml --config .swiftlint-analyze.yml --compiler-log-path build-ios.log
```
Expected: no violations. Delete `build-ios.log` afterwards; do not commit it.

- [ ] **Step 5: Commit**

```bash
git add -A DiceKeys/Model/Recipes DiceKeys/Features/Recipes/CustomRecipeModel.swift Tests/DiceKeysTests
git commit -m "Build and read recipes through the parsed tree"
```

---

### Task 4: The raw JSON builder reports what is wrong

**Files:**
- Modify: `DiceKeys/Features/Recipes/CustomRecipeModel.swift:111-116, 127-128`
- Test: `Tests/DiceKeysTests/RecipeBuildingTests.swift`

**Interfaces:**
- Consumes: `String.canonicalizedRecipe()`, `RecipeJsonError.message`
- Produces: `CustomRecipeModel.progress` becomes `.error(message)` for raw JSON that is not an object.

- [ ] **Step 1: Write the failing tests**

Append to `Tests/DiceKeysTests/RecipeBuildingTests.swift` (inside the suite):

```swift
    @Test("raw JSON that is not an object is reported, not passed through")
    @MainActor
    func rawJsonErrors() {
        let model = CustomRecipeModel(type: .Password)
        model.buildType = .rawJson
        model.rawJsonString = "[]"
        #expect(model.progress == .error(RecipeJsonError.notAnObject.message))
        model.rawJsonString = #"{"purpose":"x",}"#
        #expect(model.progress == .error(RecipeJsonError.invalid(offset: 15).message))
        model.rawJsonString = "   "
        #expect(model.progress == .incomplete)
        model.rawJsonString = #"{ "#":2, "purpose":"x" }"#
        #expect(model.progress.recipe?.recipe == #"{"purpose":"x","#":2}"#)
    }
```

- [ ] **Step 2: Run the test to verify it fails**

Same command as Task 1 Step 2 with `-only-testing:DiceKeysTests/RecipeBuildingTests/rawJsonErrors`. Expected: the `[]` expectation fails (the temporary line from Task 3 passes `[]` through as `.ready`).

- [ ] **Step 3: Report the error**

In `CustomRecipeModel.update()`, replace the `.rawJson` branch of the second `switch buildType` (currently `recipe = rawJsonString.canonicalizeRecipeJson()` or the Task 3 stand-in) with:

```swift
        case .rawJson:
            do {
                recipe = try rawJsonString.canonicalizedRecipe()
            } catch {
                progress = .error(error.message)
                return
            }
```

`error` is typed `RecipeJsonError` because `canonicalizedRecipe()` declares `throws(RecipeJsonError)`, so `.message` resolves without a cast.

- [ ] **Step 4: Run the tests to verify they pass**

Run the whole `DiceKeysTests` target. Expected: all pass. `swiftlint lint --strict --quiet`: no output.

- [ ] **Step 5: Commit**

```bash
git add DiceKeys/Features/Recipes/CustomRecipeModel.swift Tests/DiceKeysTests/RecipeBuildingTests.swift
git commit -m "Reject raw JSON recipes that are not objects, with the reason"
```

---

### Task 5: Docs and the pull request

**Files:**
- Modify: `docs/ARCHITECTURE.md` (wherever `CanonicalizeJsonRecipe` is named; check with `grep -n Canonicalize docs/*.md`)

- [ ] **Step 1: Update the architecture doc**

Run `grep -rn "CanonicalizeJsonRecipe\|canonicalizeRecipeJson" docs README.md`. For each hit, replace the file name with `RecipeJson.swift` and, if the sentence describes the canonicalizer, make it say: "`RecipeJson.swift` parses a recipe keeping the source text of numbers and strings and writes the reference canonical form (sorted fields, `purpose` first, `#` last, no whitespace)". Do not add a section; the one-line mention is enough.

- [ ] **Step 2: Run the full app test target and lint once more**

Same commands as Task 3 Step 4 (tests, lint, analyze). Expected: green, no output.

- [ ] **Step 3: Commit and push**

```bash
git add docs
git commit -m "Name the recipe JSON file in the architecture doc"
git push -u origin worktree-derivation-rewrite
```

- [ ] **Step 4: Open the PR**

Title: `Canonicalize recipe JSON the way the reference app does`

Body (problem, decisions, evidence; no diff narration):

```
Raw JSON recipes were canonicalized through JSONSerialization, which rewrote what the user typed: true became 1, 1.50 became 1.5, \/ became /, duplicate keys collapsed to the first, and non-ASCII keys sorted by Swift's String order. The TypeScript and Android apps keep the source text, so a hand-typed recipe derived a different secret here than there.

## Decisions

- The canonicalizer parses the text itself and keeps the original characters of every number and string, following the TypeScript reference. Keys sort by UTF-16 code unit, as JavaScript compares them.
- Object keys are written back as their original quoted text. The reference decodes them, which produces invalid JSON for a key containing an escape; for every other key the two agree.
- Raw JSON that is not a JSON object is now reported in the builder instead of being passed through verbatim, since nothing downstream could derive from it anyway.
- The design spec for the derivation rewrite this starts is included under docs/superpowers/specs; it is deleted when the last PR of the sequence lands.

Verified: the reference's own canonicalization test cases, the Android cases the app already carried, and fixed-point tests for numbers, escapes, booleans and duplicates.
```

Create with `gh pr create --base main --head worktree-derivation-rewrite --title "..." --body "..."`.
