//
//  PasswordFormatter.swift
//  Derivation
//

/// The word count, then hyphen-joined words with the first capitalized. Each 8-byte block
/// picks a word modulo the list size, unbiased because the sizes are powers of two.
enum PasswordFormatter {
    static let bytesPerWord = 8

    static func password(from secret: [UInt8], wordList: WordList, lengthInChars: Int?) -> String {
        let words = wordList.words
        var chosen = [String]()
        var offset = 0
        while offset + bytesPerWord <= secret.count {
            var value: UInt64 = 0
            for byte in secret[offset..<offset + bytesPerWord] {
                value = value << 8 | UInt64(byte)
            }
            chosen.append(words[Int(value % UInt64(words.count))])
            offset += bytesPerWord
        }
        var joined = String(chosen.count)
        if let first = chosen.first {
            joined += "-" + first.prefix(1).uppercased() + first.dropFirst()
        }
        for word in chosen.dropFirst() {
            joined += "-" + word
        }
        if let lengthInChars {
            return String(joined.prefix(lengthInChars))
        }
        return joined
    }
}
