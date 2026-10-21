//
//  PasswordFormatter.swift
//  Derivation
//

/// Writes a passphrase from derived bytes. Each 8-byte block picks one entry, the block
/// modulo the list size; what is left of the block, the quotient, is independent of that
/// pick and supplies a memorable passphrase's digits and its uppercase word.
enum PasswordFormatter {
    static let bytesPerEntry = 8
    private static let hyphen = "-"

    typealias Entry = (word: String, quotient: UInt64)

    static func entries(from secret: [UInt8], list: PassphraseList) -> [Entry] {
        let words = list.words
        let size = UInt64(words.count)
        var chosen: [Entry] = []
        var offset = 0
        while offset + bytesPerEntry <= secret.count {
            var value: UInt64 = 0
            for byte in secret[offset..<offset + bytesPerEntry] {
                value = value << 8 | UInt64(byte)
            }
            chosen.append((words[Int(value % size)], value / size))
            offset += bytesPerEntry
        }
        return chosen
    }

    static func passphrase(from secret: [UInt8], style: PassphraseStyle) -> String {
        switch style {
        case .random(_, let symbols):
            entries(from: secret, list: PassphraseStyle.characterList(symbols: symbols)).map(\.word).joined()
        case .memorable(_, let digitsAndUppercase):
            memorable(entries(from: secret, list: .effLarge), digitsAndUppercase: digitsAndUppercase)
        }
    }

    /// Hyphens between lowercase words, or joined by digits with one word upper-cased: the digit after word
    /// `i` is block `i`'s quotient modulo 10, and the word upper-cased is at the last
    /// block's quotient modulo the word count.
    private static func memorable(_ entries: [Entry], digitsAndUppercase: Bool) -> String {
        var words = entries.map(\.word)
        guard digitsAndUppercase else { return words.joined(separator: hyphen) }
        if let last = entries.last {
            let index = Int(last.quotient % UInt64(words.count))
            words[index] = words[index].uppercased()
        }
        var joined = ""
        for (index, word) in words.enumerated() {
            if index > 0 { joined += String(entries[index - 1].quotient % 10) }
            joined += word
        }
        return joined
    }
}
