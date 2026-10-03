//
//  PasswordStrength.swift
//  DiceKeys
//

import Derivation

/// What the password sheet says about a choice before anything is derived. Every value here
/// is uniformly random, so guesses are 2^bits and zxcvbn's bands apply directly
/// (https://github.com/dropbox/zxcvbn, "score" in its README).
enum PasswordStrength {
    enum Band: Int, CaseIterable {
        case tooGuessable, veryGuessable, somewhatGuessable, safelyUnguessable, veryUnguessable

        var label: String {
            switch self {
            case .tooGuessable: return "too guessable"
            case .veryGuessable: return "very guessable"
            case .somewhatGuessable: return "somewhat guessable"
            case .safelyUnguessable: return "safely unguessable"
            case .veryUnguessable: return "very unguessable"
            }
        }
    }

    /// The bits in one decimal digit, log2(10): a ten-entry list carries exactly that.
    private static let bitsPerDigit = WordList.digits.bitsPerEntry
    /// zxcvbn's thresholds, 10^3, 10^6, 10^8 and 10^10 guesses, in bits.
    private static let bandCeilings = [3.0, 6, 8, 10].map { $0 * bitsPerDigit }

    static func bits(list: WordList, entries: Int, separator: Separator) -> Double {
        let digits = separator == .digits ? Double(max(entries - 1, 0)) * bitsPerDigit : 0
        return list.bits(forWords: entries) + digits
    }

    /// How many whole entries fit in `maximumCharacters` whatever the derivation picks: the
    /// longest entry plus the separator per entry, less the separator the last one lacks.
    static func guaranteedEntries(list: WordList, entries: Int, separator: Separator, maximumCharacters: Int) -> Int {
        let separatorWidth = separator == .empty ? 0 : 1
        let fit = (maximumCharacters + separatorWidth) / (list.longestWordLength + separatorWidth)
        return min(entries, fit)
    }

    static func band(bits: Double) -> Band {
        Band.allCases[bandCeilings.filter { bits >= $0 }.count]
    }
}
