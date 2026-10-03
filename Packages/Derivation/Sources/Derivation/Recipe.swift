//
//  Recipe.swift
//  Derivation
//

/// A recipe, parsed and validated. `json` is the text exactly as given, because that text
/// is what gets hashed. A field defined only for another type is salt and is not read,
/// except `algorithm`, which only keys may name.
public struct Recipe: Sendable, Equatable {
    public let json: String
    public let type: DerivableType
    public let hashFunction: HashFunction
    public let lengthInBytes: Int
    public let lengthInChars: Int?
    public let wordList: WordList
    /// Password only; 0 for every other type.
    public let lengthInWords: Int
    /// Password only; `.reference` for every other type.
    public let joining: Joining

    /// The longest output the HKDF construction can produce.
    public static let maximumLengthInBytes = HKDFBlake2b.maximumOutputLength
    public static let maximumLengthInWords = maximumLengthInBytes / PasswordFormatter.bytesPerWord

    /// A secret's length when the recipe names none.
    public static let defaultLengthInBytes = 32
    /// The fixed length of every key type.
    public static let keyLengthInBytes = 32
    private static let defaultLengthInBits = 128

    public static let purposeField = "purpose"
    /// The sequence number, written as `#` so it sorts after every other field.
    public static let sequenceNumberField = "#"
    public static let lengthInCharsField = "lengthInChars"
    public static let lengthInBytesField = "lengthInBytes"
    public static let wordListField = "wordList"
    public static let lengthInBitsField = "lengthInBits"
    public static let lengthInWordsField = "lengthInWords"
    public static let separatorField = "separator"
    public static let capitalizeField = "capitalize"

    public init(json: String, type: DerivableType) throws(DerivationError) {
        let fields = try Recipe.parse(json)
        self.json = json
        self.type = type

        if let declared = try fields.string("type"), declared != type.rawValue {
            throw .typeMismatch(recipe: declared, requested: type)
        }
        if let algorithm = try fields.string("algorithm") {
            let expected: String? =
                switch type {
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
            let listName = try fields.string(Recipe.wordListField) ?? WordList.en512.rawValue
            guard let wordList = WordList(rawValue: listName) else { throw .unknownWordList(listName) }
            self.wordList = wordList
            let bits = try fields.integer(Recipe.lengthInBitsField, in: 1...wordList.maximumLengthInBits)
            let words = try fields.integer(Recipe.lengthInWordsField, in: 1...Recipe.maximumLengthInWords)
            let chars = try fields.integer(Recipe.lengthInCharsField, in: 1...Int.max)
            self.lengthInChars = chars
            // Type-checked like every integer field, then overridden: the words decide the length.
            _ = try fields.integer(Recipe.lengthInBytesField, in: Int.min...Int.max)
            let resolvedWords: Int
            switch (bits, words) {
            case (nil, nil):
                if wordList.kind == .characters, let chars {
                    // A character set's length is in characters, so the field that says
                    // "characters" sets how many are derived, and truncation is then a no-op.
                    guard chars <= Recipe.maximumLengthInWords else {
                        throw .outOfRange(field: Recipe.lengthInCharsField, allowed: 1...Recipe.maximumLengthInWords)
                    }
                    resolvedWords = chars
                } else {
                    resolvedWords = wordList.words(forBits: Recipe.defaultLengthInBits)
                }
            case (nil, let words?):
                resolvedWords = words
            case (let bits?, nil):
                resolvedWords = wordList.words(forBits: bits)
            case (let bits?, let words?):
                guard words == wordList.words(forBits: bits) else { throw .bitsAndWordsConflict }
                resolvedWords = words
            }
            self.lengthInWords = resolvedWords
            self.lengthInBytes = resolvedWords * PasswordFormatter.bytesPerWord
            self.joining = try Recipe.joining(of: fields, for: wordList)
        case .secret:
            self.lengthInBytes =
                try fields.integer(Recipe.lengthInBytesField, in: 1...Recipe.maximumLengthInBytes)
                ?? Recipe.defaultLengthInBytes
            self.lengthInChars = nil
            self.wordList = .en512
            self.lengthInWords = 0
            self.joining = .reference
        case .symmetricKey, .unsealingKey, .signingKey:
            if let bytes = try fields.integer(Recipe.lengthInBytesField, in: Int.min...Int.max),
                bytes != Recipe.keyLengthInBytes
            {
                throw .lengthMustBe32(type)
            }
            self.lengthInBytes = Recipe.keyLengthInBytes
            self.lengthInChars = nil
            self.wordList = .en512
            self.lengthInWords = 0
            self.joining = .reference
        }
    }

    /// A character set has exactly one joining, so it refuses any other. A word list is
    /// joined the reference way unless `separator` is given; `capitalize` means nothing
    /// without a separator, so alone it is an error rather than silently ignored.
    private static func joining(of fields: RecipeFields, for wordList: WordList) throws(DerivationError) -> Joining {
        let separatorText = try fields.string(separatorField)
        let capitalize = try fields.boolean(capitalizeField)
        switch wordList.kind {
        case .characters:
            if let separatorText, !separatorText.isEmpty { throw .invalidJoining }
            if capitalize == true { throw .invalidJoining }
            return .modern(separator: .empty, capitalize: false)
        case .words:
            guard let separatorText else {
                if capitalize != nil { throw .invalidJoining }
                return .reference
            }
            guard let separator = Separator(rawValue: separatorText) else { throw .unknownSeparator(separatorText) }
            return .modern(separator: separator, capitalize: capitalize ?? false)
        }
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
            if !digits.isEmpty, digits.utf8.allSatisfy(\.isDigit) {
                throw .outOfRange(field: name, allowed: allowed)
            }
            throw .wrongType(field: name, expected: "an integer")
        }
        guard allowed.contains(value) else { throw .outOfRange(field: name, allowed: allowed) }
        return value
    }

    func boolean(_ name: String) throws(DerivationError) -> Bool? {
        guard let field = fields.first(where: { $0.name == name }) else { return nil }
        guard case .bool(let value) = field.value else { throw .wrongType(field: name, expected: "true or false") }
        return value
    }
}
