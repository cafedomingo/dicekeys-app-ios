//
//  SealingKeys.swift
//  SeededCrypto
//
//  Public-key sealing (X25519 + XSalsa20-Poly1305 sealed boxes).
//

import Foundation
import SeededCryptoNative

/// The public half: anyone holding it can seal messages that only the matching
/// `UnsealingKey` can open.
public struct SealingKey: Sendable, Hashable {
    public let json: String
    public let recipe: String
    public let sealingKeyBytes: Data

    private struct Fields: Decodable {
        let keyBytes: String
        let recipe: String
    }

    init(nativeJson json: String) throws {
        let fields = try Native.decode(Fields.self, from: json)
        self.json = json
        self.recipe = fields.recipe
        self.sealingKeyBytes = try Data.fromNativeHex(fields.keyBytes, field: "keyBytes")
    }

    public static func from(json: String) throws -> SealingKey {
        try SealingKey(nativeJson: Native.string { out, err in dkc_sealing_key_from_json(json, out, err) })
    }

    public func toJson() -> String { json }

    /// Seals raw bytes. (Named `with:` to match the previous Objective-C import of `sealWithData:`.)
    public func seal(with data: Data, unsealingInstructions: String = "") throws -> PackagedSealedMessage {
        let packaged = try Native.withBytes(data) { bytes, count in
            try Native.string { out, err in
                dkc_sealing_key_seal(json, bytes, count, unsealingInstructions, out, err)
            }
        }
        return try PackagedSealedMessage(nativeJson: packaged)
    }

    public func seal(withMessage message: String, unsealingInstructions: String = "") throws -> PackagedSealedMessage {
        try seal(with: Data(message.utf8), unsealingInstructions: unsealingInstructions)
    }
}

/// The private half, derived from a seed and a recipe.
public struct UnsealingKey: Sendable, Hashable {
    public let json: String
    public let recipe: String
    public let unsealingKeyBytes: Data
    public let sealingKeyBytes: Data
    private let publicKey: SealingKey

    private struct Fields: Decodable {
        let recipe: String
        let sealingKeyBytes: String
        let unsealingKeyBytes: String
    }

    init(nativeJson json: String) throws {
        let fields = try Native.decode(Fields.self, from: json)
        self.json = json
        self.recipe = fields.recipe
        self.unsealingKeyBytes = try Data.fromNativeHex(fields.unsealingKeyBytes, field: "unsealingKeyBytes")
        self.sealingKeyBytes = try Data.fromNativeHex(fields.sealingKeyBytes, field: "sealingKeyBytes")
        self.publicKey = try SealingKey(nativeJson: Native.string { out, err in dkc_unsealing_key_sealing_key(json, out, err) })
    }

    public static func deriveFromSeed(withSeedString seedString: String, recipe: String) throws -> UnsealingKey {
        try UnsealingKey(nativeJson: Native.string { out, err in dkc_unsealing_key_derive(seedString, recipe, out, err) })
    }

    public static func from(json: String) throws -> UnsealingKey {
        try UnsealingKey(nativeJson: Native.string { out, err in dkc_unsealing_key_from_json(json, out, err) })
    }

    public func toJson() -> String { json }

    public func sealingKey() -> SealingKey { publicKey }

    public func unseal(withPackagedSealedMessage packagedSealedMessage: PackagedSealedMessage) throws -> Data {
        try unseal(withJsonPackagedSealedMessage: packagedSealedMessage.json)
    }

    public func unseal(withJsonPackagedSealedMessage packagedSealedMessageJson: String) throws -> Data {
        try Native.bytes { out, err in dkc_unsealing_key_unseal(json, packagedSealedMessageJson, out, err) }
    }

    public func unseal(ciphertext: Data, unsealingInstructions: String = "") throws -> Data {
        try Native.withBytes(ciphertext) { bytes, count in
            try Native.bytes { out, err in
                dkc_unsealing_key_unseal_ciphertext(json, bytes, count, unsealingInstructions, out, err)
            }
        }
    }

    /// Unseals using only the seed; the key is re-derived from the recipe inside the message.
    public static func unseal(withJsonPackagedSealedMessage packagedSealedMessageJson: String, seedString: String) throws -> Data {
        try Native.bytes { out, err in dkc_seed_unseal_with_unsealing_key(seedString, packagedSealedMessageJson, out, err) }
    }
}
