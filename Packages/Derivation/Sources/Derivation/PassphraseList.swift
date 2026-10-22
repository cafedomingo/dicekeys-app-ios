//
//  PassphraseList.swift
//  Derivation
//

import Foundation

/// The lists a passphrase recipe may name. An entry is chosen as an 8-byte block modulo the
/// list size. A name is part of the format: neither a name nor an entry can change.
public enum PassphraseList: String, CaseIterable, Sendable {
    case effLarge = "eff_large_wordlist"
    case lettersDigitsSymbols = "letters-digits-symbols"
    case lettersDigits = "letters-digits"

    public var words: [String] {
        switch self {
        case .effLarge: effLargeWords
        case .lettersDigitsSymbols: CharacterSets.lettersDigitsSymbols
        case .lettersDigits: CharacterSets.lettersDigits
        }
    }

    public var count: Int { words.count }

    /// The choice one entry carries: log2 of the size.
    public var bitsPerEntry: Double { log2(Double(count)) }
}
