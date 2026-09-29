//
//  PackagedSealedMessage.swift
//  SeededCrypto
//

import Foundation
import SeededCryptoNative

/// Ciphertext bundled with the recipe of the key that sealed it and any
/// unsealing instructions, so the holder of the seed can unseal it later.
public struct PackagedSealedMessage: Sendable, Hashable {
    public let json: String
    public let ciphertext: Data
    public let recipe: String
    /// Empty when the message carries no unsealing instructions.
    public let unsealingInstructions: String

    private struct Fields: Decodable {
        let ciphertext: String
        let recipe: String?
        let unsealingInstructions: String?
    }

    init(nativeJson json: String) throws {
        let fields = try Native.decode(Fields.self, from: json)
        self.json = json
        self.ciphertext = try Data.fromNativeHex(fields.ciphertext, field: "ciphertext")
        self.recipe = fields.recipe ?? ""
        self.unsealingInstructions = fields.unsealingInstructions ?? ""
    }

    public static func from(json: String) throws -> PackagedSealedMessage {
        try PackagedSealedMessage(nativeJson: Native.string { out, err in dkc_packaged_sealed_message_from_json(json, out, err) })
    }

    public func toJson() -> String { json }
}
