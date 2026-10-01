//
//  OpenSSH.swift
//  KeyFormats
//

import CryptoKit
import Foundation
import Derivation

/// OpenSSH encodings of an Ed25519 signing key (PROTOCOL.key).
public enum OpenSSH {
    static let keyType = "ssh-ed25519"
    /// PROTOCOL.key: the file starts with this NUL-terminated magic.
    private static let authMagic = Array("openssh-key-v1\0".utf8)
    /// The cipher and KDF names of a key stored without a passphrase.
    private static let unencrypted = "none"
    /// PROTOCOL.key: the private section is padded to the cipher's block size, 8 for "none".
    private static let paddingBlockSize = 8
    /// The container could hold several keys; this writes one.
    private static let keyCount: UInt32 = 1

    /// `ssh-ed25519 <base64> DiceKeys`. The comment is fixed so the line users paste into
    /// servers stays the same.
    public static func publicKeyLine(_ key: Derivation.SigningKey) -> String {
        "\(keyType) " + Data(publicKeyBlob(key)).base64EncodedString() + " DiceKeys"
    }

    /// An unencrypted `openssh-key-v1` block. The check value, random in OpenSSH, is derived
    /// from the public key so the export is deterministic.
    public static func privateKeyPEM(_ key: Derivation.SigningKey, comment: String = "") -> String {
        let publicKey = Array(key.verificationKeyBytes)
        let checkValue = Array(SHA256.hash(data: key.verificationKeyBytes).prefix(4))
        var section = ByteWriter()
        section.append(checkValue)
        section.append(checkValue)
        section.sshString(keyType)
        section.sshString(publicKey)
        section.sshString(Array(key.signingKeyBytes))
        section.sshString(comment)
        var padding: UInt8 = 1
        while section.count % paddingBlockSize != 0 {
            section.byte(padding)
            padding += 1
        }
        var blob = ByteWriter()
        blob.append(authMagic)
        blob.sshString(unencrypted)
        blob.sshString(unencrypted)
        blob.sshString("")
        blob.uint32(keyCount)
        blob.sshString(publicKeyBlob(key))
        blob.sshString(section.bytes)
        return Armor.pem("OPENSSH PRIVATE KEY", blob.bytes, crc: false)
    }

    private static func publicKeyBlob(_ key: Derivation.SigningKey) -> [UInt8] {
        var blob = ByteWriter()
        blob.sshString(keyType)
        blob.sshString(Array(key.verificationKeyBytes))
        return blob.bytes
    }
}
