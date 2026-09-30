//
//  Recipe.swift
//  Derivation
//

/// A recipe, parsed and validated. `json` is the text exactly as given, because that text
/// is what gets hashed; every other property is what the text means for `type`.
///
/// Parsing is strict where the reference C++ was lenient: integers must be JSON integers,
/// every length is bounded, and unknown names for `hashFunction`, `wordList` and
/// `algorithm` are errors. Fields the format defines for other types, and every field it
/// does not define, are salt only and are not read.
public struct Recipe: Sendable, Equatable {
    public let json: String
    public let type: DerivableType
    public let hashFunction: HashFunction
    /// The number of bytes the hash must produce: the secret's length, a key's 32, or a
    /// password's words times 8.
    public let lengthInBytes: Int
    public let lengthInChars: Int?
    public let wordList: WordList
    /// Password only; 0 for every other type.
    public let lengthInWords: Int

    /// The longest output the HKDF construction can produce: 255 blocks of 32 bytes.
    public static let maximumLengthInBytes = 8160
    public static let maximumLengthInWords = maximumLengthInBytes / 8

    public init(json: String, type: DerivableType) throws(DerivationError) {
        let fields = try Recipe.parse(json)
        self.json = json
        self.type = type

        if let declared = try fields.string("type"), declared != type.rawValue {
            throw .typeMismatch(recipe: declared, requested: type)
        }
        if let algorithm = try fields.string("algorithm") {
            let expected: String? = switch type {
            case .symmetricKey: "XSalsa20Poly1305"
            case .unsealingKey: "X25519"
            case .signingKey: "Ed25519"
            case .password, .secret: nil
            }
            guard algorithm == expected else { throw .invalidAlgorithm(algorithm) }
        }
        let hashName = try fields.string("hashFunction") ?? HashFunction.blake2b.rawValue
        guard let hashFunction = HashFunction(rawValue: hashName) else { throw .unsupportedHashFunction(hashName) }
        self.hashFunction = hashFunction

        switch type {
        case .password:
            let listName = try fields.string("wordList") ?? WordList.en512.rawValue
            guard let wordList = WordList(rawValue: listName) else { throw .unknownWordList(listName) }
            self.wordList = wordList
            let bitsPerWord = wordList.bitsPerWord
            let bitsRange = 1...(Recipe.maximumLengthInWords * bitsPerWord)
            let bits = try fields.integer("lengthInBits", in: bitsRange)
            let words = try fields.integer("lengthInWords", in: 1...Recipe.maximumLengthInWords)
            self.lengthInChars = try fields.integer("lengthInChars", in: 1...Int.max)
            // A lengthInBytes on a password is salt: the words decide the length.
            _ = try fields.integer("lengthInBytes", in: Int.min...Int.max)
            let resolvedWords: Int
            switch (bits, words) {
            case (nil, nil):
                resolvedWords = Recipe.wordsFor(bits: 128, bitsPerWord: bitsPerWord)
            case (nil, let words?):
                resolvedWords = words
            case (let bits?, nil):
                resolvedWords = Recipe.wordsFor(bits: bits, bitsPerWord: bitsPerWord)
            case (let bits?, let words?):
                guard words == Recipe.wordsFor(bits: bits, bitsPerWord: bitsPerWord) else { throw .bitsAndWordsConflict }
                resolvedWords = words
            }
            self.lengthInWords = resolvedWords
            self.lengthInBytes = resolvedWords * 8
        case .secret:
            self.lengthInBytes = try fields.integer("lengthInBytes", in: 1...Recipe.maximumLengthInBytes) ?? 32
            self.lengthInChars = nil
            self.wordList = .en512
            self.lengthInWords = 0
        case .symmetricKey, .unsealingKey, .signingKey:
            if let bytes = try fields.integer("lengthInBytes", in: Int.min...Int.max), bytes != 32 {
                throw .lengthMustBe32(type)
            }
            self.lengthInBytes = 32
            self.lengthInChars = nil
            self.wordList = .en512
            self.lengthInWords = 0
        }
    }

    private static func wordsFor(bits: Int, bitsPerWord: Int) -> Int {
        (bits + bitsPerWord - 1) / bitsPerWord
    }

    private static func parse(_ json: String) throws(DerivationError) -> RecipeFields {
        if json.isEmpty { return RecipeFields(fields: []) }
        do {
            return RecipeFields(fields: try RecipeJsonParser.parseObject(json))
        } catch {
            switch error {
            case .notAnObject: throw .recipeNotAnObject
            case .duplicateKey(let name, _): throw .duplicateField(name)
            case .invalid, .unrepresentableKey: throw .invalidJson(error.message)
            }
        }
    }
}

/// Typed access to the parsed fields, reading each one at most once.
private struct RecipeFields {
    let fields: [RecipeJsonField]

    func string(_ name: String) throws(DerivationError) -> String? {
        guard let field = fields.first(where: { $0.name == name }) else { return nil }
        guard case .string(let quoted) = field.value else { throw .wrongType(field: name, expected: "a string") }
        do {
            return try RecipeJsonParser.decodeString(quoted: quoted)
        } catch {
            throw .invalidJson(error.message)
        }
    }

    func integer(_ name: String, in allowed: ClosedRange<Int>) throws(DerivationError) -> Int? {
        guard let field = fields.first(where: { $0.name == name }) else { return nil }
        guard case .number(let text) = field.value else { throw .wrongType(field: name, expected: "an integer") }
        guard let value = Int(text) else {
            // A JSON integer too large for Int is out of range, not the wrong type.
            let digits = text.hasPrefix("-") ? text.dropFirst() : Substring(text)
            if !digits.isEmpty, digits.utf8.allSatisfy({ $0 >= 0x30 && $0 <= 0x39 }) {
                throw .outOfRange(field: name, allowed: allowed)
            }
            throw .wrongType(field: name, expected: "an integer")
        }
        guard allowed.contains(value) else { throw .outOfRange(field: name, allowed: allowed) }
        return value
    }
}
