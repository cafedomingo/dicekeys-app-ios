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
