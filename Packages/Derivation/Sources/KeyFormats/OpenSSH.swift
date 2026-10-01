//
//  OpenSSH.swift
//  KeyFormats
//

import Derivation
import SeededCrypto

/// The OpenSSH encodings of an Ed25519 signing key. The vendored C++ produces them until
/// the Swift encoder lands.
public enum OpenSSH {
    /// One line: `ssh-ed25519 <base64> DiceKeys`.
    public static func publicKeyLine(_ key: Derivation.SigningKey) throws -> String {
        try SeededCrypto.SigningKey.from(json: key.toJson()).openSshPublicKey
    }

    /// An unencrypted `openssh-key-v1` block, with the comment stored inside it.
    public static func privateKeyPEM(_ key: Derivation.SigningKey, comment: String = "") throws -> String {
        try SeededCrypto.SigningKey.from(json: key.toJson()).openSshPemPrivateKey(comment: comment)
    }
}
