//
//  Mnemonic.swift
//  KeyFormats
//

import CryptoKit

/// BIP39 (https://github.com/bitcoin/bips/blob/master/bip-0039.mediawiki): entropy bytes to
/// a checksummed word phrase. Adapted from pengpengliu/BIP39; see THIRD_PARTY_LICENSES.
enum Mnemonic {
    // Entropy -> Mnemonic
    static func toMnemonic(_ bytes: [UInt8], wordlist: [String] = Wordlist.english) -> [String] {
        let entropyBits = String(bytes.flatMap { ("00000000" + String($0, radix: 2)).suffix(8) })
        let checksumBits = Mnemonic.deriveChecksumBits(bytes)
        let bits = entropyBits + checksumBits

        var phrase = [String]()
        for i in 0..<(bits.count / 11) {
            let wi = Int(bits[bits.index(bits.startIndex, offsetBy: i * 11)..<bits.index(bits.startIndex, offsetBy: (i + 1) * 11)], radix: 2)!
            phrase.append(String(wordlist[wi]))
        }
        return phrase
    }

    static func deriveChecksumBits(_ bytes: [UInt8]) -> String {
        let ENT = bytes.count * 8
        let CS = ENT / 32

        let hash = SHA256.hash(data: bytes)
        let hashbits = String(hash.flatMap { ("00000000" + String($0, radix: 2)).suffix(8) })
        return String(hashbits.prefix(CS))
    }
}
