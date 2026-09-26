//
//  CanonicalizeJsonRecipe.swift
//  DiceKeys
//
//  Created by Angelos Veglektsis on 7/29/22.
//

import Foundation

// These functions should match the
// [Reference Implementation in TypeScript](https://github.com/dicekeys/dicekeys-app-typescript/blob/main/web/src/dicekeys/canonicalizeRecipeJson.ts)
// and its functionality should not be changed without ensuring that the reference implementation
// and dependent implementations are changed to match.

func compareObjectFieldNames(a: String, b: String) -> Bool {
    // The "#" (sequence number) field always comes last
    if a == "#" {
        return false
    } else if b == "#" {
        return true
    }

    // The "purpose" field always comes first
    else if a == "purpose" {
        return true
    } else if b == "purpose" {
        return false
    }
    // Otherwise, sort in alphabetical order
    else {
        return a < b
    }
}

func toCanonicalizeRecipeJson(_ json: Any) -> String {
    if (json as? NSNull) != nil {
         return "null"
    }

    if let json = json as? [Any] {
        let values = json.map { data in
            toCanonicalizeRecipeJson(data)
        }.joined(separator: ",")

        return "[\(values)]"
    }

    if let json = json as? [String: Any] {
        // Sort keys
        let keys = json.keys.sorted { a, b in
            return compareObjectFieldNames(a: a, b: b)
        }
        let values: [String] = keys.map { key in
            return "\(quotedJsonString(key)):\(toCanonicalizeRecipeJson(json[key]!))"
        }

        return "{\(values.joined(separator: ","))}"
    }

    if let json = json as? String {
        return quotedJsonString(json)
    } else {
        return "\(json)"
    }
}

/// Quotes a parsed string for JSON output. The reference keeps each string exactly as it was
/// quoted in the input; this re-escapes quotes, backslashes and control characters, which
/// gives the same text for any input that used those escapes.
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
