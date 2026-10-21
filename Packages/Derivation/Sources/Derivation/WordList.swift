//
//  WordList.swift
//  Derivation
//

import Foundation

/// The lists a password recipe may name. An entry is chosen as an 8-byte block modulo the
/// list size. A name is part of the format: a recipe that names one derives a value every
/// version of this app must reproduce, so neither a name nor an entry can change.
public enum WordList: String, CaseIterable, Sendable {
    case en512 = "EN_512_words_5_chars_max_ed_4_20200917"
    case en1024 = "EN_1024_words_6_chars_max_ed_4_20200917"
    case effLarge = "EFF_large_7776_words_9_chars_max_20160719"
    case lettersDigitsSymbols = "CHARS_67_letters_digits_symbols_20261002"
    case lettersDigits = "CHARS_57_letters_digits_20261002"

    /// What an entry is, which decides the unit of length and how entries are joined.
    public enum Kind: Sendable {
        /// English words: separators, capitalization, length in words.
        case words
        /// One character each: concatenated, length in characters.
        case characters
    }

    public var kind: Kind {
        switch self {
        case .en512, .en1024, .effLarge: return .words
        case .lettersDigitsSymbols, .lettersDigits: return .characters
        }
    }

    public var words: [String] {
        switch self {
        case .en512: return en512Words
        case .en1024: return en1024Words
        case .effLarge: return effLargeWords
        case .lettersDigitsSymbols: return CharacterSets.lettersDigitsSymbols
        case .lettersDigits: return CharacterSets.lettersDigits
        }
    }

    public var count: Int { words.count }

    /// The choice one entry carries: log2 of the size.
    public var bitsPerEntry: Double { log2(Double(count)) }

    /// The fewest entries whose combinations reach 2^bits. Floating point is safe because no
    /// allowed bit count lands near a whole number of entries, which
    /// `WordListTests.wordsForBits` checks against exact arithmetic for every list.
    public func words(forBits bits: Int) -> Int { Int((Double(bits) / bitsPerEntry).rounded(.up)) }

    public func bits(forWords words: Int) -> Double { Double(words) * bitsPerEntry }

    /// The largest `lengthInBits` whose entry count is still `Recipe.maximumLengthInWords`.
    public var maximumLengthInBits: Int { Int(bits(forWords: Recipe.maximumLengthInWords)) }

    public var longestWordLength: Int { words.reduce(0) { max($0, $1.count) } }
}
