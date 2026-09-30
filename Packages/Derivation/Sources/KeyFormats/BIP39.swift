//
//  BIP39.swift
//  KeyFormats
//

import Foundation

/// A BIP39 mnemonic for a derived secret: the standard way to carry a wallet seed.
public enum BIP39 {
    public enum Error: Swift.Error, Equatable {
        /// BIP39 allows 128 to 256 bits of entropy in 32-bit steps.
        case invalidEntropyLength(Int)
    }

    public static func mnemonic(entropy: Data) throws -> String {
        guard (16...32).contains(entropy.count), entropy.count % 4 == 0 else {
            throw Error.invalidEntropyLength(entropy.count)
        }
        return Mnemonic.toMnemonic([UInt8](entropy)).joined(separator: " ")
    }
}
