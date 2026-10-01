//
//  RecipeJson.swift
//  Derivation
//

import Foundation

/// A JSON value that keeps the source text of numbers and strings, so its canonical text
/// matches the reference canonicalizeRecipeJson.ts character for character.
public indirect enum RecipeJsonValue: Equatable {
    case object([RecipeJsonField])
    case array([RecipeJsonValue])
    /// The original quoted text, quotes and escapes included.
    case string(quoted: String)
    /// The original sign, digits, fraction and exponent.
    case number(text: String)
    case bool(Bool)
    case null

    public static func text(_ value: String) -> RecipeJsonValue {
        .string(quoted: quotedJsonString(value))
    }

    public static func int(_ value: Int) -> RecipeJsonValue {
        .number(text: String(value))
    }

    /// No whitespace, fields sorted, source text preserved.
    public var canonicalText: String {
        switch self {
        case .object(let fields):
            let sorted = fields.enumerated().sorted { lhs, rhs in
                if RecipeJsonField.precedes(lhs.element.name, rhs.element.name) { return true }
                if RecipeJsonField.precedes(rhs.element.name, lhs.element.name) { return false }
                return lhs.offset < rhs.offset
            }
            // Names are written decoded between plain quotes, unescaped; the parser rejects
            // names for which that would not be valid JSON.
            return "{"
                + sorted.map { "\"\($0.element.name)\":\($0.element.value.canonicalText)" }.joined(separator: ",") + "}"
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

public struct RecipeJsonField: Equatable {
    /// The decoded name, used for ordering and written back between plain quotes.
    public let name: String
    public let value: RecipeJsonValue

    public init(name: String, value: RecipeJsonValue) {
        self.name = name
        self.value = value
    }

    /// "#" (the sequence number) always comes last and "purpose" always first; the rest sort
    /// by UTF-16 code unit, which is what JavaScript's `<` on strings compares.
    public static func precedes(_ lhs: String, _ rhs: String) -> Bool {
        if lhs.utf16.elementsEqual(rhs.utf16) { return false }
        if lhs == Recipe.sequenceNumberField { return false }
        if rhs == Recipe.sequenceNumberField { return true }
        if lhs == Recipe.purposeField { return true }
        if rhs == Recipe.purposeField { return false }
        return lhs.utf16.lexicographicallyPrecedes(rhs.utf16)
    }
}

/// The first code point JSON allows unescaped; everything below it is a control character
/// (RFC 8259 section 7).
private let firstUnescapedCodePoint: UInt8 = 0x20

/// RFC 8259 section 7: a code point outside the Basic Multilingual Plane is written as a
/// pair of `\u` escapes from these two ranges.
private let highSurrogates: ClosedRange<UInt32> = 0xD800...0xDBFF
private let lowSurrogates: ClosedRange<UInt32> = 0xDC00...0xDFFF
private let firstSupplementaryCodePoint: UInt32 = 0x10000

/// Quotes a string as `JSON.stringify` does: quotes, backslashes and control characters
/// escaped, everything else raw.
public func quotedJsonString(_ string: String) -> String {
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
        case _ where scalar.value < UInt32(firstUnescapedCodePoint): quoted += String(format: "\\u%04x", scalar.value)
        default: quoted.unicodeScalars.append(scalar)
        }
    }
    return quoted + "\""
}

public enum RecipeJsonError: Error, Equatable {
    case notAnObject
    /// Byte offset into the UTF-8 text where parsing stopped.
    case invalid(offset: Int)
    /// A field name that cannot be written between plain quotes.
    case unrepresentableKey(offset: Int)
    case duplicateKey(name: String, offset: Int)

    static let notAnObjectMessage = "A recipe must be a JSON object, such as {\"purpose\":\"example\"}"

    public var message: String {
        switch self {
        case .notAnObject: return Self.notAnObjectMessage
        case .invalid(let offset): return "Not valid JSON near position \(offset)"
        case .duplicateKey: return "Each field name may appear only once"
        case .unrepresentableKey: return "A field name cannot contain quotes, backslashes or control characters"
        }
    }
}

/// A strict RFC 8259 parser that records where each number and string came from instead of
/// converting it, because the recipe's exact text is what gets hashed.
public struct RecipeJsonParser {
    private let bytes: [UInt8]
    private var index = 0
    private var depth = 0
    /// Parsing recurses once per level. Debug builds on a 512 KB thread (the Swift
    /// concurrency pool) overflow between 250 and 400 levels, so the bound stays well below.
    private static let maximumDepth = 128
    private static let utf8ByteOrderMark: [UInt8] = [0xEF, 0xBB, 0xBF]
    /// A `\u` escape is a backslash, the `u` and four hex digits.
    private static let hexDigitsPerEscape = 4
    private static let unicodeEscapeLength = 2 + hexDigitsPerEscape

    private init(_ text: String) {
        bytes = Array(text.utf8)
    }

    /// Parses a document that must be a single object, tolerating a leading byte order mark.
    public static func parseObject(_ text: String) throws(RecipeJsonError) -> [RecipeJsonField] {
        var parser = RecipeJsonParser(text)
        if parser.bytes.starts(with: utf8ByteOrderMark) { parser.index = utf8ByteOrderMark.count }
        parser.skipWhitespace()
        guard parser.peek == UInt8(ascii: "{") else {
            // Empty input or valid JSON of another kind is "not an object"; the rest is invalid.
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

    public static func decodeString(quoted: String) throws(RecipeJsonError) -> String {
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
        case UInt8(ascii: "t"):
            try expect("true")
            return .bool(true)
        case UInt8(ascii: "f"):
            try expect("false")
            return .bool(false)
        case UInt8(ascii: "n"):
            try expect("null")
            return .null
        case UInt8(ascii: "-"), UInt8(ascii: "0")...UInt8(ascii: "9"): return try parseNumber()
        default: throw .invalid(offset: index)
        }
    }

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
        if peek == UInt8(ascii: "}") {
            index += 1
            return .object(fields)
        }
        while true {
            skipWhitespace()
            guard peek == UInt8(ascii: "\"") else { throw .invalid(offset: index) }
            let nameStart = index
            _ = try parseString()
            let name = try decode(quotedRange: nameStart..<index)
            guard
                name.unicodeScalars.allSatisfy({
                    $0 != "\"" && $0 != "\\" && $0.value >= UInt32(firstUnescapedCodePoint)
                })
            else {
                throw .unrepresentableKey(offset: nameStart)
            }
            // Reference implementations disagree on duplicates (one keeps the last value), so
            // no handling could match everywhere.
            guard !fields.contains(where: { $0.name.utf16.elementsEqual(name.utf16) }) else {
                throw .duplicateKey(name: name, offset: nameStart)
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
            case UInt8(ascii: "}"):
                index += 1
                return .object(fields)
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
        if peek == UInt8(ascii: "]") {
            index += 1
            return .array(items)
        }
        while true {
            skipWhitespace()
            items.append(try parseValue())
            skipWhitespace()
            switch peek {
            case UInt8(ascii: ","): index += 1
            case UInt8(ascii: "]"):
                index += 1
                return .array(items)
            default: throw .invalid(offset: index)
            }
        }
    }

    /// Validates a string's escapes and returns its source text with the quotes.
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
            case 0x00..<firstUnescapedCodePoint:
                throw .invalid(offset: index)
            default:
                index += 1
            }
        }
    }

    private mutating func parseHex4() throws(RecipeJsonError) -> UInt32 {
        var value: UInt32 = 0
        for _ in 0..<Self.hexDigitsPerEscape {
            guard let byte = peek, let digit = Character(UnicodeScalar(byte)).hexDigitValue else {
                throw .invalid(offset: index)
            }
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
                let length =
                    switch byte {
                    case ..<0x80: 1
                    case ..<0xE0: 2
                    case ..<0xF0: 3
                    default: 4
                    }
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
                cursor += Self.hexDigitsPerEscape
                if highSurrogates.contains(unit) {
                    try flushSurrogate()
                    pendingHighSurrogate = (unit, cursor - Self.unicodeEscapeLength)
                    continue
                }
                if lowSurrogates.contains(unit) {
                    guard let high = pendingHighSurrogate else {
                        throw .invalid(offset: cursor - Self.unicodeEscapeLength)
                    }
                    pendingHighSurrogate = nil
                    let combined =
                        firstSupplementaryCodePoint + ((high.value - highSurrogates.lowerBound) << 10)
                        + (unit - lowSurrogates.lowerBound)
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

extension UInt8 {
    var isDigit: Bool { self >= UInt8(ascii: "0") && self <= UInt8(ascii: "9") }
}

extension String {
    public func canonicalizedRecipe() throws(RecipeJsonError) -> String {
        RecipeJsonValue.object(try RecipeJsonParser.parseObject(self)).canonicalText
    }
}
