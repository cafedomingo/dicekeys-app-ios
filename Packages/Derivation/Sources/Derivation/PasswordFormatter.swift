//
//  PasswordFormatter.swift
//  Derivation
//

/// Writes a password from derived bytes. Each 8-byte block picks one entry, the block
/// modulo the list size; what is left of the block, the quotient, is independent of that
/// pick and supplies the digit separators and the capitalized word of the modern joining.
enum PasswordFormatter {
    static let bytesPerWord = 8
    private static let referenceSeparator = "-"

    typealias Entry = (word: String, quotient: UInt64)

    static func entries(from secret: [UInt8], wordList: WordList) -> [Entry] {
        let words = wordList.words
        let size = UInt64(words.count)
        var chosen: [Entry] = []
        var offset = 0
        while offset + bytesPerWord <= secret.count {
            var value: UInt64 = 0
            for byte in secret[offset..<offset + bytesPerWord] {
                value = value << 8 | UInt64(byte)
            }
            chosen.append((words[Int(value % size)], value / size))
            offset += bytesPerWord
        }
        return chosen
    }

    static func password(from secret: [UInt8], wordList: WordList, joining: Joining, lengthInChars: Int?) -> String {
        let entries = entries(from: secret, wordList: wordList)
        let joined =
            switch joining {
            case .reference: reference(entries.map(\.word))
            case .modern(let separator, let capitalize): modern(entries, separator: separator, capitalize: capitalize)
            }
        if let lengthInChars {
            return String(joined.prefix(lengthInChars))
        }
        return joined
    }

    /// The count, then hyphen-joined words with the first capitalized, as the reference did.
    private static func reference(_ words: [String]) -> String {
        var joined = String(words.count)
        if let first = words.first {
            joined += referenceSeparator + first.prefix(1).uppercased() + first.dropFirst()
        }
        for word in words.dropFirst() {
            joined += referenceSeparator + word
        }
        return joined
    }

    private static func modern(_ entries: [Entry], separator: Separator, capitalize: Bool) -> String {
        var words = entries.map(\.word)
        if capitalize, let last = entries.last {
            let index = Int(last.quotient % UInt64(words.count))
            words[index] = words[index].uppercased()
        }
        var joined = ""
        for (index, word) in words.enumerated() {
            if index > 0 {
                joined += separator == .digits ? String(entries[index - 1].quotient % 10) : separator.rawValue
            }
            joined += word
        }
        return joined
    }
}
