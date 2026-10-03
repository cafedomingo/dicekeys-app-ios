//
//  PasswordRecipeChoices.swift
//  DiceKeys
//

import Derivation

/// What the password sheet lets a user choose, and the recipe fields those choices write.
/// A field is written only when it differs from the format's default, except `separator`,
/// which marks the modern joining, so an unchanged choice leaves no trace in the recipe.
struct PasswordRecipeChoices: Equatable {
    enum Kind: CaseIterable {
        case memorable, random, pin

        var title: String {
            switch self {
            case .memorable: return "Memorable Password"
            case .random: return "Random Password"
            case .pin: return "PIN Code"
            }
        }
    }

    static let memorableLists: [WordList] = [.effLarge, .en512, .en1024, .emoji]
    static let wordCountRange = 3...24
    static let characterCountRange = 8...64
    static let pinLengthRange = 4...12
    static let maximumCharactersRange = 16...999
    private static let defaultLengthInBits = 128

    var kind: Kind = .memorable
    var memorableList: WordList = .effLarge
    var wordCount = 6
    var separator: Separator = .hyphen
    var capitalize = false
    var maximumCharacters: Int?
    var characterCount = 20
    var numbers = true
    var symbols = true
    var pinLength = 6

    /// Text-field view of `maximumCharacters`: empty means no limit; values outside
    /// `maximumCharactersRange` are ignored.
    var maximumCharactersEntry: Int? {
        get { maximumCharacters }
        set {
            guard let newValue else {
                maximumCharacters = nil
                return
            }
            if Self.maximumCharactersRange.contains(newValue) { maximumCharacters = newValue }
        }
    }

    /// The list the recipe names.
    var wordList: WordList {
        switch kind {
        case .memorable: return memorableList
        case .random:
            switch (numbers, symbols) {
            case (true, true): return .lettersDigitsSymbols
            case (true, false): return .lettersDigits
            case (false, true): return .lettersSymbols
            case (false, false): return .letters
            }
        case .pin: return .digits
        }
    }

    /// Words, characters or digits, whichever the list counts in.
    var entries: Int {
        switch kind {
        case .memorable: return wordCount
        case .random: return characterCount
        case .pin: return pinLength
        }
    }

    /// Character lists have one joining; the separator choice is kept for when the user
    /// returns to a word list.
    var effectiveSeparator: Separator {
        wordList.kind == .characters ? .empty : separator
    }

    var fields: [RecipeJsonField] {
        var fields: [RecipeJsonField] = []
        let list = wordList
        if list != .en512 {
            fields.append(RecipeJsonField(name: Recipe.wordListField, value: .text(list.rawValue)))
        }
        switch list.kind {
        case .characters:
            fields.append(RecipeJsonField(name: Recipe.lengthInCharsField, value: .int(entries)))
        case .words:
            if entries != list.words(forBits: Self.defaultLengthInBits) {
                fields.append(RecipeJsonField(name: Recipe.lengthInWordsField, value: .int(entries)))
            }
            fields.append(RecipeJsonField(name: Recipe.separatorField, value: .text(separator.rawValue)))
            if capitalize {
                fields.append(RecipeJsonField(name: Recipe.capitalizeField, value: .bool(true)))
            }
            if let maximumCharacters {
                fields.append(RecipeJsonField(name: Recipe.lengthInCharsField, value: .int(maximumCharacters)))
            }
        }
        return fields
    }
}
