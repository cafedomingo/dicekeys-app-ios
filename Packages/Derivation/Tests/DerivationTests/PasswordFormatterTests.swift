//
//  PasswordFormatterTests.swift
//  DerivationTests
//

import Testing

@testable import Derivation

@Suite("Passphrase entries")
struct PasswordFormatterTests {
    private let eff = PassphraseList.effLarge.words
    private let size = UInt64(PassphraseList.effLarge.count)

    @Test("an entry is its 8-byte big-endian block modulo the list size, and the quotient is kept")
    func entries() {
        let entries = PasswordFormatter.entries(from: blocks([size * 17 + 5, size * 3 + 300, 7]), list: .effLarge)
        #expect(entries.map(\.word) == [eff[5], eff[300], eff[7]])
        #expect(entries.map(\.quotient) == [17, 3, 0])
    }

    @Test("random characters concatenate")
    func random() {
        let characters = PassphraseList.lettersDigitsSymbols.words
        let passphrase = PasswordFormatter.passphrase(
            from: blocks([0, 1, 9, 66]), style: .random(length: 4, symbols: true))
        #expect(passphrase == characters[0] + characters[1] + characters[9] + characters[66])
    }

    @Test("memorable words join with hyphens, all lowercase")
    func memorable() {
        let passphrase = PasswordFormatter.passphrase(
            from: blocks([size * 4, 1, 2]), style: .memorable(words: 3, digitsAndUppercase: false))
        #expect(passphrase == [eff[0], eff[1], eff[2]].joined(separator: "-"))
    }

    /// Quotients 17, 3 and 4 give digits 7 and 3, and 4 mod 3 words upper-cases the second word.
    @Test(
        "a digit is the preceding block's quotient modulo 10; the uppercase word is the last quotient modulo the count")
    func digitsAndUppercase() {
        let passphrase = PasswordFormatter.passphrase(
            from: blocks([size * 17, size * 3 + 1, size * 4 + 2]), style: .memorable(words: 3, digitsAndUppercase: true)
        )
        #expect(passphrase == eff[0] + "7" + eff[1].uppercased() + "3" + eff[2])
    }
}

/// 8-byte big-endian blocks from the given values.
private func blocks(_ values: [UInt64]) -> [UInt8] {
    values.flatMap { value in (0..<8).map { UInt8(truncatingIfNeeded: value >> (8 * (7 - $0))) } }
}
