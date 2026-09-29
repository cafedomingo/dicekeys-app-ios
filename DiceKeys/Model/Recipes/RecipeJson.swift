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
            // The reference writes the decoded name between plain quotes, without escaping it.
            // The parser rejects names for which that would not be valid JSON.
            return "{" + sorted.map { "\"\($0.element.name)\":\($0.element.value.canonicalText)" }.joined(separator: ",") + "}"
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
    /// The decoded name, used for ordering and written back between plain quotes.
    let name: String
    let value: RecipeJsonValue

    /// "#" (the sequence number) always comes last and "purpose" always first; the rest sort
    /// by UTF-16 code unit, which is what JavaScript's `<` on strings compares.
    static func precedes(_ lhs: String, _ rhs: String) -> Bool {
        if lhs.utf16.elementsEqual(rhs.utf16) { return false }
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

enum RecipeJsonError: Error, Equatable {
    case notAnObject
    /// Byte offset into the UTF-8 text where parsing stopped.
    case invalid(offset: Int)
    /// A field name whose decoded text the reference would write as invalid JSON.
    case unrepresentableKey(offset: Int)
    /// A field name that appears twice in one object.
    case duplicateKey(offset: Int)

    var message: String {
        switch self {
        case .notAnObject: return "A recipe must be a JSON object, such as {\"purpose\":\"example\"}"
        case .invalid(let offset): return "Not valid JSON near position \(offset)"
        case .duplicateKey: return "Each field name may appear only once"
        case .unrepresentableKey: return "A field name cannot contain quotes, backslashes or control characters"
        }
    }
}

/// A strict RFC 8259 parser that records where each number and string came from instead of
/// converting it, because the recipe's exact text is what gets hashed.
struct RecipeJsonParser {
    private let bytes: [UInt8]
    private var index = 0
    private var depth = 0
    /// Parsing and serializing recurse once per level, so pasted text nested thousands deep
    /// would overflow the stack. Debug builds on a 512 KB thread (the Swift concurrency pool)
    /// overflowed between 250 and 400 levels, so this stays well below that; no real recipe
    /// nests more than a few levels.
    private static let maximumDepth = 128

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
        _ = try parser.parseString()
        guard parser.index == parser.bytes.count else { throw .invalid(offset: parser.index) }
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
        case UInt8(ascii: "\""): return .string(quoted: try parseString())
        case UInt8(ascii: "t"): try expect("true"); return .bool(true)
        case UInt8(ascii: "f"): try expect("false"); return .bool(false)
        case UInt8(ascii: "n"): try expect("null"); return .null
        case UInt8(ascii: "-"), UInt8(ascii: "0")...UInt8(ascii: "9"): return try parseNumber()
        default: throw .invalid(offset: index)
        }
    }

    /// Counts one more open bracket; the caller decrements on leaving.
    private mutating func enterNesting() throws(RecipeJsonError) {
        depth += 1
        guard depth <= Self.maximumDepth else { throw .invalid(offset: index) }
    }

    private mutating func parseObjectBody() throws(RecipeJsonError) -> RecipeJsonValue {
        try enterNesting()
        defer { depth -= 1 }
        index += 1
        var fields: [RecipeJsonField] = []
        skipWhitespace()
        if peek == UInt8(ascii: "}") { index += 1; return .object(fields) }
        while true {
            skipWhitespace()
            guard peek == UInt8(ascii: "\"") else { throw .invalid(offset: index) }
            let nameStart = index
            _ = try parseString()
            let name = try decode(quotedRange: nameStart..<index)
            guard name.unicodeScalars.allSatisfy({ $0 != "\"" && $0 != "\\" && $0.value >= 0x20 }) else {
                throw .unrepresentableKey(offset: nameStart)
            }
            // The reference's order for equal names is engine-dependent and the C++ library
            // keeps the last value, so no order of duplicates could match everywhere.
            guard !fields.contains(where: { $0.name.utf16.elementsEqual(name.utf16) }) else {
                throw .duplicateKey(offset: nameStart)
            }
            skipWhitespace()
            guard peek == UInt8(ascii: ":") else { throw .invalid(offset: index) }
            index += 1
            skipWhitespace()
            let value = try parseValue()
            fields.append(RecipeJsonField(name: name, value: value))
            skipWhitespace()
            switch peek {
            case UInt8(ascii: ","): index += 1
            case UInt8(ascii: "}"): index += 1; return .object(fields)
            default: throw .invalid(offset: index)
            }
        }
    }

    private mutating func parseArray() throws(RecipeJsonError) -> RecipeJsonValue {
        try enterNesting()
        defer { depth -= 1 }
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
    private mutating func parseString() throws(RecipeJsonError) -> String {
        let start = index
        index += 1
        while true {
            guard let byte = peek else { throw .invalid(offset: index) }
            switch byte {
            case UInt8(ascii: "\""):
                index += 1
                return String(decoding: bytes[start..<index], as: UTF8.self)
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
