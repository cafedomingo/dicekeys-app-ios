//
//  OpenPGP.swift
//  KeyFormats
//

import Derivation
import SeededCrypto

/// The OpenPGP secret key block for an Ed25519 signing key. The vendored C++ produces it
/// until the Swift encoder lands.
public enum OpenPGP {
    /// Timestamp 0 keeps the fingerprint stable across derivations; the fingerprint hashes
    /// the creation time.
    public static func secretKeyBlock(_ key: Derivation.SigningKey, userId: String = "", timestamp: UInt32 = 0) throws -> String {
        try SeededCrypto.SigningKey.from(json: key.toJson()).openPgpPemFormatSecretKey(userId: userId, timestamp: timestamp)
    }
}
