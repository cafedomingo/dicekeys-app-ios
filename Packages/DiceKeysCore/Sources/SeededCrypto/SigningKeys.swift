//
//  SigningKeys.swift
//  SeededCrypto
//
//  Ed25519 signing and verification, plus the OpenSSH / OpenPGP encodings of the key.
//

import Foundation
import SeededCryptoNative

/// The public half of a signing key.
public struct SignatureVerificationKey: Sendable, Hashable {
    public let json: String
    public let recipe: String
    public let signatureVerificationKeyBytes: Data

    private struct Fields: Decodable {
        let keyBytes: String
        let recipe: String
    }

    init(nativeJson json: String) throws {
        let fields = try Native.decode(Fields.self, from: json)
        self.json = json
        self.recipe = fields.recipe
        self.signatureVerificationKeyBytes = try Data.fromNativeHex(fields.keyBytes, field: "keyBytes")
    }

    public static func deriveFromSeed(withSeedString seedString: String, recipe: String) throws -> SignatureVerificationKey {
        try SignatureVerificationKey(nativeJson: Native.string { out, err in dkc_signature_verification_key_derive(seedString, recipe, out, err) })
    }

    public static func from(json: String) throws -> SignatureVerificationKey {
        try SignatureVerificationKey(nativeJson: Native.string { out, err in dkc_signature_verification_key_from_json(json, out, err) })
    }

    public func toJson() -> String { json }

    public var openSshPublicKey: String {
        get throws {
            try Native.string { out, err in dkc_signature_verification_key_open_ssh_public_key(json, out, err) }
        }
    }

    /// Verifies a signature over raw bytes. (Named `with:` to match the previous Objective-C import of `verifyWithData:`.)
    public func verify(with data: Data, signature: Data) throws -> Bool {
        try Native.withBytes(data) { message, messageCount in
            try Native.withBytes(signature) { sig, sigCount in
                try Native.flag { verified, err in
                    dkc_signature_verification_key_verify(json, message, messageCount, sig, sigCount, verified, err)
                }
            }
        }
    }

    public func verify(withMessage message: String, signature: Data) throws -> Bool {
        try verify(with: Data(message.utf8), signature: signature)
    }
}

/// An Ed25519 signing key derived from a seed and a recipe.
public struct SigningKey: Sendable, Hashable {
    public let json: String
    public let recipe: String
    public let signingKeyBytes: Data
    public let signatureVerificationKey: SignatureVerificationKey
    public let openSshPublicKey: String
    public let openSshPemPrivateKey: String
    public let openPgpPemFormatSecretKey: String

    public var signatureVerificationKeyBytes: Data { signatureVerificationKey.signatureVerificationKeyBytes }

    private struct Fields: Decodable {
        let recipe: String
        let signingKeyBytes: String
    }

    init(nativeJson json: String) throws {
        let fields = try Native.decode(Fields.self, from: json)
        self.json = json
        self.recipe = fields.recipe
        self.signingKeyBytes = try Data.fromNativeHex(fields.signingKeyBytes, field: "signingKeyBytes")
        self.signatureVerificationKey = try SignatureVerificationKey(
            nativeJson: Native.string { out, err in dkc_signing_key_signature_verification_key(json, out, err) }
        )
        // The previous Objective-C wrapper used an empty comment, an empty user id and
        // timestamp 0 for these encodings; keep that so existing exported keys match.
        self.openSshPublicKey = try Native.string { out, err in dkc_signing_key_open_ssh_public_key(json, out, err) }
        self.openSshPemPrivateKey = try Native.string { out, err in dkc_signing_key_open_ssh_pem_private_key(json, "", out, err) }
        self.openPgpPemFormatSecretKey = try Native.string { out, err in dkc_signing_key_open_pgp_pem_secret_key(json, "", 0, out, err) }
    }

    public static func deriveFromSeed(withSeedString seedString: String, recipe: String) throws -> SigningKey {
        try SigningKey(nativeJson: Native.string { out, err in dkc_signing_key_derive(seedString, recipe, out, err) })
    }

    public static func from(json: String) throws -> SigningKey {
        try SigningKey(nativeJson: Native.string { out, err in dkc_signing_key_from_json(json, out, err) })
    }

    public func toJson() -> String { json }

    /// Signs raw bytes. (Named `with:` to match the previous Objective-C import of `generateSignatureWithData:`.)
    public func generateSignature(with data: Data) throws -> Data {
        try Native.withBytes(data) { bytes, count in
            try Native.bytes { out, err in dkc_signing_key_sign(json, bytes, count, out, err) }
        }
    }

    public func generateSignature(withMessage message: String) throws -> Data {
        try generateSignature(with: Data(message.utf8))
    }

    public static func generateSignature(withMessage message: String, seedString: String, recipe: String) throws -> Data {
        try deriveFromSeed(withSeedString: seedString, recipe: recipe).generateSignature(withMessage: message)
    }

    /// OpenPGP secret key block with a caller-chosen user id and creation timestamp.
    public func openPgpPemFormatSecretKey(userId: String, timestamp: UInt32) throws -> String {
        try Native.string { out, err in dkc_signing_key_open_pgp_pem_secret_key(json, userId, timestamp, out, err) }
    }

    /// OpenSSH private key block with a caller-chosen comment.
    public func openSshPemPrivateKey(comment: String) throws -> String {
        try Native.string { out, err in dkc_signing_key_open_ssh_pem_private_key(json, comment, out, err) }
    }
}
