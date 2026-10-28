//
//  KeyRecipe.swift
//  Derivation
//

import Foundation

/// What a catalog entry derives. Each kind derives an ordered list of algorithms from its one
/// recipe, which is `kind` and `name`, plus a passphrase's style.
public enum KeyKind: String, CaseIterable, Codable, Sendable {
    case ssh
    case wireguard
    case age
    case passphrase
    case wallet

    /// Passphrases and wallets are a secret alone, with no public half.
    public var hasPublicKey: Bool {
        switch self {
        case .ssh, .wireguard, .age: true
        case .passphrase, .wallet: false
        }
    }

    /// Every algorithm a key of this kind derives, from its one recipe, in the order shown.
    /// Append only: an algorithm, once released, is never removed or retyped. Reordering for
    /// emphasis is fine, since nothing stored depends on order.
    public var algorithms: [DerivableType] {
        switch self {
        case .ssh: [.ed25519]
        case .wireguard: [.x25519]
        case .age: [.x25519, .mlkem768x25519]
        case .passphrase: [.passphrase]
        case .wallet: [.bip39]
        }
    }
}

/// How a passphrase is written. The settings are part of its recipe, so part of the key.
public enum PassphraseStyle: Hashable, Codable, Sendable {
    /// Letters and digits without look-alikes, with `!@#$%&*-_?` when `symbols` is set.
    case random(length: Int, symbols: Bool)
    /// Lowercase words from the memorable word list joined by hyphens, or by digits with one whole word upper-cased.
    case memorable(words: Int, digitsAndUppercase: Bool)

    public static let randomLengths = 12...64
    public static let memorableWords = 4...10
    public static let standard = PassphraseStyle.random(length: 24, symbols: false)
    public static let standardMemorable = PassphraseStyle.memorable(words: 6, digitsAndUppercase: false)

    /// Exact, since every character or word is uniform; the separator digits and the
    /// uppercase word add a little that this leaves out.
    public var bits: Double {
        switch self {
        case .random(let length, let symbols): Double(length) * Self.characterList(symbols: symbols).bitsPerEntry
        case .memorable(let words, _): Double(words) * PassphraseList.effLarge.bitsPerEntry
        }
    }

    static func characterList(symbols: Bool) -> PassphraseList { symbols ? .lettersDigitsSymbols : .lettersDigits }

    /// Characters or words, one 8-byte block each.
    var entryCount: Int {
        switch self {
        case .random(let length, _): length
        case .memorable(let words, _): words
        }
    }

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
    /// Text that is not exactly the canonical text of a recipe.
    case notARecipe
}

/// A kind, a name and, for a passphrase, a style, and the recipe text they make: the RFC 8785
/// (JCS) canonical form of those fields. The text is hashed into every key as HKDF's info, so
/// writing any field differently would change every key of that kind.
///
/// The `defaults` have no name, and every DiceKey has them.
public struct KeyRecipe: Hashable, Sendable {
    public static let maximumNameLength = 64
    /// The one invisible character a name may hold: emoji sequences such as 👩‍💻 need it.
    private static let zeroWidthJoiner: Unicode.Scalar = "\u{200D}"

    /// The SSH and age keys of every DiceKey. Each is its recipe text as a literal, which is
    /// what gets hashed, so the field writer can never change a default key.
    public static let defaults = [
        KeyRecipe(kind: .ssh, pinnedText: #"{"kind":"ssh"}"#),
        KeyRecipe(kind: .age, pinnedText: #"{"kind":"age"}"#)
    ]

    public let kind: KeyKind
    /// Nil only for a default.
    public let name: String?
    /// Set for a passphrase, nil for every other kind.
    public let style: PassphraseStyle?
    private let pinnedText: String?

    public var isDefault: Bool { pinnedText != nil }

    private init(kind: KeyKind, pinnedText: String) {
        self.kind = kind
        name = nil
        style = nil
        self.pinnedText = pinnedText
    }

    public init(kind: KeyKind, name: String, style: PassphraseStyle = .standard) throws(KeyRecipeError) {
        self.kind = kind
        self.name = try Self.normalizedName(name)
        if kind == .passphrase {
            guard style.isInRange else { throw .styleOutOfRange }
            self.style = style
        } else {
            self.style = nil
        }
        pinnedText = nil
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

    /// The recipe as RFC 8785 canonical JSON, the text that is hashed.
    public var json: String {
        if let pinnedText { return pinnedText }
        return CanonicalJSON.object(
            Dictionary(uniqueKeysWithValues: fields.members.map { ($0.key.rawValue, $0.value) }))
    }

    /// The JSON fields this recipe writes, for a format that holds a recipe among fields of its
    /// own and must tell the two apart.
    public var fieldNames: [String] { fields.members.map(\.key.rawValue) }

    /// Recipe text is a recipe only if it is exactly that recipe's canonical text: the text is
    /// what gets hashed, so any other spelling of the same fields would be a different key.
    /// Compared as UTF-8 bytes, because `==` on strings ignores a difference in normalization.
    public init(json: String) throws(KeyRecipeError) {
        guard let recipe = try? JSONDecoder().decode(KeyRecipe.self, from: Data(json.utf8)),
            recipe.json.utf8.elementsEqual(json.utf8)
        else { throw .notARecipe }
        self = recipe
    }

    fileprivate var fields: RecipeFields {
        var fields = RecipeFields(kind: kind.rawValue, name: name)
        switch style {
        case nil:
            break
        case .random(let length, let symbols):
            fields.length = length
            fields.list = PassphraseStyle.characterList(symbols: symbols).rawValue
        case .memorable(let words, let digitsAndUppercase):
            fields.length = words
            fields.list = PassphraseList.effLarge.rawValue
            fields.separator = digitsAndUppercase ? Self.digitsSeparator : Self.hyphenSeparator
            if digitsAndUppercase { fields.uppercase = true }
        }
        return fields
    }

    fileprivate static let hyphenSeparator = "-"
    fileprivate static let digitsSeparator = "digits"
}

/// A recipe as JSON fields: the shape of the hashed text, and of each key in the catalog
/// and on paper. Decoding accepts a recipe only if its fields are exactly the ones its own
/// recipe would write, the name byte for byte, so no field is read loosely. A recipe with no
/// name is a default or nothing. A field that isn't a recipe's is left to the format holding
/// the recipe, which knows its own fields.
extension KeyRecipe: Codable {
    public init(from decoder: any Decoder) throws {
        let fields = try RecipeFields(from: decoder)
        if let recipe = Self.defaults.first(where: { $0.fields == fields }) {
            self = recipe
            return
        }
        guard let kind = KeyKind(rawValue: fields.kind), let name = fields.name,
            let recipe = try? KeyRecipe(kind: kind, name: name, style: fields.style ?? .standard),
            recipe.fields == fields, recipe.name?.utf8.elementsEqual(name.utf8) == true
        else { throw KeyRecipeError.notARecipe }
        self = recipe
    }

    public func encode(to encoder: any Encoder) throws {
        try fields.encode(to: encoder)
    }
}

/// A recipe's JSON fields, in the format's spelling.
private struct RecipeFields: Codable, Equatable {
    var kind: String
    var name: String?
    var length: Int?
    var list: String?
    var separator: String?
    var uppercase: Bool?

    enum CodingKeys: String, CodingKey {
        case kind, name, length, list, separator, uppercase
    }

    init(kind: String, name: String?) {
        self.kind = kind
        self.name = name
    }

    /// The fields that are set, with their JSON values.
    var members: [(key: CodingKeys, value: CanonicalJSON.Value)] {
        [(.kind, .string(kind))]
            + [
                name.map { (CodingKeys.name, CanonicalJSON.Value.string($0)) },
                length.map { (CodingKeys.length, CanonicalJSON.Value.integer($0)) },
                list.map { (.list, .string($0)) },
                separator.map { (.separator, .string($0)) },
                uppercase.map { (.uppercase, .boolean($0)) }
            ].compactMap(\.self)
    }

    /// The passphrase style these fields describe, if any; `KeyRecipe`'s check that its own
    /// fields come out the same rejects every combination this reads loosely.
    var style: PassphraseStyle? {
        guard let length, let list = list.flatMap(PassphraseList.init(rawValue:)) else { return nil }
        switch list {
        case .effLarge: return .memorable(words: length, digitsAndUppercase: separator == KeyRecipe.digitsSeparator)
        case .lettersDigits, .lettersDigitsSymbols:
            return .random(length: length, symbols: list == .lettersDigitsSymbols)
        }
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

    /// JCS escapes strings as `JSON.stringify` does, which `quotedJsonString` implements.
    static func object(_ fields: [String: Value]) -> String {
        let members = fields.sorted { $0.key.utf16.lexicographicallyPrecedes($1.key.utf16) }
            .map { quotedJsonString($0.key) + ":" + value($0.value) }
        return "{" + members.joined(separator: ",") + "}"
    }

    private static func value(_ value: Value) -> String {
        switch value {
        case .string(let text): quotedJsonString(text)
        case .integer(let number): String(number)
        case .boolean(let flag): flag ? "true" : "false"
        }
    }
}

/// Below this, a character is written as an escape.
private let firstUnescapedScalar: UInt32 = 0x20

/// A JSON string literal escaped as RFC 8785 section 3.2.2.2 requires.
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
        case _ where scalar.value < firstUnescapedScalar: quoted += String(format: "\\u%04x", scalar.value)
        default: quoted.unicodeScalars.append(scalar)
        }
    }
    return quoted + "\""
}
