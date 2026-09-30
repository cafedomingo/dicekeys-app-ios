//
//  OpenSSH.swift
//  KeyFormats
//

import CryptoKit
import Foundation
import Derivation

/// The OpenSSH encodings of an Ed25519 signing key (PROTOCOL.key in the OpenSSH sources).
public enum OpenSSH {
    static let keyType = "ssh-ed25519"

    /// One line: `ssh-ed25519 <base64> DiceKeys`. The comment is fixed because the reference
    /// implementation fixed it, and the line is what users have pasted into servers.
    public static func publicKeyLine(_ key: Derivation.SigningKey) -> String {
        "\(keyType) " + Data(publicKeyBlob(key)).base64EncodedString() + " DiceKeys"
    }

    /// An unencrypted `openssh-key-v1` block. The check value, random in OpenSSH because
    /// it exists to detect a wrong passphrase, is derived from the public key so the export
    /// is the same every time.
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
        while section.count % 8 != 0 {
            section.byte(padding)
            padding += 1
        }
        var blob = ByteWriter()
        blob.append(Array("openssh-key-v1\0".utf8))
        blob.sshString("none")
        blob.sshString("none")
        blob.sshString("")
        blob.uint32(1)
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
