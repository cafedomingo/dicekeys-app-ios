//
//  PasswordStrength.swift
//  DiceKeys
//

import Derivation

/// What the password sheet says about a choice before anything is derived. Every value here
/// is uniformly random, so its strength is exactly its bits. No standard maps bits to a
/// score (NIST SP 800-63B rev. 4 sets none), so the bar's scale is this app's choice: full at
/// 80 bits, about where 1Password's generator fills its bar for the same passwords.
enum PasswordStrength {
    /// The bar's color, from red to green.
    enum Tier: CaseIterable {
        case weak, fair, good, strong
    }

    static let fullBarBits = 80.0
    /// Where fair, good and strong begin.
    private static let tierFloors = [40.0, 50, 60]
    /// The bits in one decimal digit, log2(10): a ten-entry list carries exactly that.
    private static let bitsPerDigit = WordList.digits.bitsPerEntry

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

    static func fill(bits: Double) -> Double { min(bits / fullBarBits, 1) }

    static func tier(bits: Double) -> Tier { Tier.allCases[tierFloors.filter { bits >= $0 }.count] }
}
