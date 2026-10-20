//
//  KeyRecipe.swift
//  Derivation
//

import Foundation

/// What a catalog entry derives. Each kind is one DiceKeys type with one recipe template.
public enum KeyKind: String, CaseIterable, Codable, Sendable {
    case ssh
    case wireguard
    case age
    case passphrase
    case wallet

    public var derivableType: DerivableType {
        switch self {
        case .ssh: .signingKey
        case .wireguard, .age: .unsealingKey
        case .passphrase: .password
        case .wallet: .secret
        }
    }
}

/// How a passphrase is written. The settings are part of its recipe, so part of the key.
public enum PassphraseStyle: Hashable, Codable, Sendable {
    /// Letters and digits without look-alikes, with `!@#$%&*-_?` when `symbols` is set.
    case random(length: Int, symbols: Bool)
    /// Words from the memorable word list joined by hyphens, or by digits with one word capitalized.
    case memorable(words: Int, digitAndCapital: Bool)

    public static let randomLengths = 12...64
    public static let memorableWords = 4...10
    public static let standard = PassphraseStyle.random(length: 24, symbols: false)

    var isInRange: Bool {
        switch self {
        case .random(let length, _): Self.randomLengths.contains(length)
        case .memorable(let words, _): Self.memorableWords.contains(words)
        }
    }
}

public enum KeyRecipeError: Error, Equatable, Sendable {
    case emptyName
    case nameTooLong(Int)
    case controlCharacterInName
    case invisibleCharacterInName
    case unassignedCharacterInName
    case styleOutOfRange
}

/// A kind, a name and, for a passphrase, a style, and the recipe text they make. The text
/// is the salt, so a changed byte in a template changes every key of that kind. The text is
/// the RFC 8785 (JCS) canonical form of the recipe's fields.
public struct KeyRecipe: Hashable, Sendable {
    public static let maximumNameLength = 64
    /// The one invisible character a name may hold: emoji sequences such as 👩‍💻 need it.
    private static let zeroWidthJoiner: Unicode.Scalar = "\u{200D}"

    public let kind: KeyKind
    public let name: String
    /// Set for a passphrase, nil for every other kind.
    public let style: PassphraseStyle?

    public init(kind: KeyKind, name: String, style: PassphraseStyle = .standard) throws(KeyRecipeError) {
        self.kind = kind
        self.name = try Self.normalizedName(name)
        if kind == .passphrase {
            guard style.isInRange else { throw .styleOutOfRange }
            self.style = style
        } else {
            self.style = nil
        }
    }

    /// Trimmed of `White_Space` at both ends and normalized to NFC; otherwise exactly as
    /// typed, because one changed character is a different key. A name can't hold what
    /// prints as nothing (control and format characters but the joiner) or what Unicode has
    /// yet to assign, whose normalization could change once it is.
    public static func normalizedName(_ name: String) throws(KeyRecipeError) -> String {
        let scalars = Array(name.unicodeScalars)
        guard let first = scalars.firstIndex(where: { !$0.properties.isWhitespace }),
            let last = scalars.lastIndex(where: { !$0.properties.isWhitespace })
        else { throw .emptyName }
        var trimmed = String.UnicodeScalarView()
        trimmed.append(contentsOf: scalars[first...last])
        let normalized = String(trimmed).precomposedStringWithCanonicalMapping
        for scalar in normalized.unicodeScalars {
            switch scalar.properties.generalCategory {
            case .control: throw .controlCharacterInName
            case .format where scalar != zeroWidthJoiner: throw .invisibleCharacterInName
            case .unassigned: throw .unassignedCharacterInName
            default: break
            }
        }
        let length = normalized.unicodeScalars.count
        guard length <= maximumNameLength else { throw .nameTooLong(length) }
        return normalized
    }

    public var json: String {
        var fields: [String: CanonicalJSON.Value] = [Recipe.purposeField: .string("\(kind.rawValue):\(name)")]
        switch style {
        case nil:
            break
        case .random(let length, let symbols):
            fields[Recipe.lengthInCharsField] = .integer(length)
            fields[Recipe.wordListField] = .string((symbols ? WordList.lettersDigitsSymbols : .lettersDigits).rawValue)
        case .memorable(let words, let digitAndCapital):
            fields[Recipe.lengthInWordsField] = .integer(words)
            fields[Recipe.separatorField] = .string(
                digitAndCapital ? Separator.digits.rawValue : Separator.hyphen.rawValue)
            fields[Recipe.wordListField] = .string(WordList.effLarge.rawValue)
            if digitAndCapital { fields[Recipe.capitalizeField] = .boolean(true) }
        }
        return CanonicalJSON.object(fields)
    }
}

/// RFC 8785 (JCS) for a flat object of strings, integers and booleans: members sorted by
/// their UTF-16 code units, no whitespace, strings escaped minimally, integers in decimal.
enum CanonicalJSON {
    enum Value {
        case string(String)
        case integer(Int)
        case boolean(Bool)
    }

    private static let shortEscapes: [Unicode.Scalar: String] = [
        "\"": "\\\"", "\\": "\\\\", "\u{08}": "\\b", "\u{0C}": "\\f", "\n": "\\n", "\r": "\\r", "\t": "\\t"
    ]
    private static let lastControlCharacter: UInt32 = 0x1F

    static func object(_ fields: [String: Value]) -> String {
        let members = fields.sorted { $0.key.utf16.lexicographicallyPrecedes($1.key.utf16) }
            .map { string($0.key) + ":" + value($0.value) }
        return "{" + members.joined(separator: ",") + "}"
    }

    static func string(_ text: String) -> String {
        var escaped = "\""
        for scalar in text.unicodeScalars {
            if let short = shortEscapes[scalar] {
                escaped += short
            } else if scalar.value <= lastControlCharacter {
                escaped += String(format: "\\u%04x", scalar.value)
            } else {
                escaped.unicodeScalars.append(scalar)
            }
        }
        return escaped + "\""
    }

    private static func value(_ value: Value) -> String {
        switch value {
        case .string(let text): string(text)
        case .integer(let number): String(number)
        case .boolean(let flag): flag ? "true" : "false"
        }
    }
}
