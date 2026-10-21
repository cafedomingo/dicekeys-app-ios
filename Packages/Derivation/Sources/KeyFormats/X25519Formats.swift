//
//  X25519Formats.swift
//  KeyFormats
//
//  An UnsealingKey's scalar is unclamped. WireGuard and age clamp a private key when they
//  use it, as CryptoKit does when it computes the public key, so all three agree on the
//  public key.
//

import Derivation
import Foundation

/// WireGuard's base64 keys (`wg genkey`, `wg pubkey`).
public enum WireGuard {
    public static func privateKey(_ key: UnsealingKey) -> String {
        key.unsealingKeyBytes.base64EncodedString()
    }

    public static func publicKey(_ key: UnsealingKey) -> String {
        key.sealingKeyBytes.base64EncodedString()
    }
}

/// age's X25519 identity and recipient (https://age-encryption.org/v1).
public enum Age {
    private static let identityPrefix = "age-secret-key-"
    private static let recipientPrefix = "age"

    /// `AGE-SECRET-KEY-1…`: Bech32 over the lower case form, then upper-cased, as
    /// `age-keygen` writes it.
    public static func identity(_ key: UnsealingKey) -> String {
        Bech32.encode(hrp: identityPrefix, bytes: Array(key.unsealingKeyBytes)).uppercased()
    }

    /// `age1…`, the recipient files are encrypted to.
    public static func recipient(_ key: UnsealingKey) -> String {
        Bech32.encode(hrp: recipientPrefix, bytes: Array(key.sealingKeyBytes))
    }
}
