//
//  WordList.swift
//  Derivation
//

/// The word lists a password recipe may name. Sizes are powers of two because a word is
/// chosen as an 8-byte block modulo the list size.
public enum WordList: String, CaseIterable, Sendable {
    case en512 = "EN_512_words_5_chars_max_ed_4_20200917"
    case en1024 = "EN_1024_words_6_chars_max_ed_4_20200917"

    public var count: Int {
        switch self {
        case .en512: return 512
        case .en1024: return 1024
        }
    }

    public var bitsPerWord: Int {
        switch self {
        case .en512: return 9
        case .en1024: return 10
        }
    }
}
