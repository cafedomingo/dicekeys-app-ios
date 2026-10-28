//
//  AgePostQuantum.swift
//  KeyFormats
//
//  age 1.3's post-quantum identity is MLKEM768-X25519, which is X-Wing: the identity is a
//  32-byte seed, which CryptoKit expands the way age does (SHAKE256 to ML-KEM-768's seed,
//  then the X25519 secret). The recipient is ML-KEM-768's encapsulation key followed by the
//  X25519 public key, 1,216 bytes.
//

import CryptoKit
import Foundation

extension Age {
    private static let postQuantumIdentityPrefix = "age-secret-key-pq-"
    private static let postQuantumRecipientPrefix = "age1pq"

    /// The identity is Bech32 over the lower case form, then upper-cased, as `age-keygen -pq`
    /// writes it. It has no fingerprint.
    public static func postQuantum(seed: Data) throws -> AlgorithmKey {
        let key = try XWingMLKEM768X25519.PrivateKey(seedRepresentation: seed, publicKey: nil)
        return AlgorithmKey(
            type: .mlkem768x25519,
            publicKey: Bech32.encode(hrp: postQuantumRecipientPrefix, bytes: Array(key.publicKey.rawRepresentation)),
            fingerprint: nil,
            secret: Bech32.encode(hrp: postQuantumIdentityPrefix, bytes: Array(seed)).uppercased())
    }
}
