//
//  BIP39.swift
//  KeyFormats
//

import CryptoKit
import Foundation

/// BIP39 mnemonics for a derived secret (https://github.com/bitcoin/bips/blob/master/bip-0039.mediawiki).
public enum BIP39 {
    private static let entropyLengthInBytes = 16...32
    private static let bitsPerWord = 11

    public enum Error: Swift.Error, Equatable {
        /// BIP39 allows 128 to 256 bits of entropy in 32-bit steps.
        case invalidEntropyLength(Int)
    }

    public static func mnemonic(entropy: Data) throws -> String {
        guard entropyLengthInBytes.contains(entropy.count), entropy.count % 4 == 0 else {
            throw Error.invalidEntropyLength(entropy.count)
        }
        return words(for: [UInt8](entropy)).joined(separator: " ")
    }

    /// The entropy followed by the first ENT/32 bits of its SHA-256, read as 11-bit word indexes.
    /// ENT is a multiple of 32, so ENT plus ENT/32 is a multiple of 11 and no bit is left over.
    static func words(for entropy: [UInt8]) -> [String] {
        let bits = entropy + Array(SHA256.hash(data: entropy))
        let wordCount = (entropy.count * 8 + entropy.count / 4) / bitsPerWord
        return (0..<wordCount).map { word in
            var index = 0
            for bit in (word * bitsPerWord)..<((word + 1) * bitsPerWord) {
                index = index << 1 | Int(bits[bit / 8] >> (7 - bit % 8) & 1)
            }
            return Wordlist.english[index]
        }
    }
}
