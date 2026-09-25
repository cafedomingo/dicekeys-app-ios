//
//  Secret.swift
//  SeededCrypto
//

import Foundation
import SeededCryptoNative

/// Raw secret bytes derived from a seed and a recipe (the basis for BIP39 seeds,
/// hardware-key seeds, and any other byte-oriented use).
public struct Secret: Sendable, Hashable {
    public let json: String
    public let recipe: String
    private let bytes: Data

    private struct Fields: Decodable {
        let secretBytes: String
        let recipe: String?
    }

    init(nativeJson json: String) throws {
        let fields = try Native.decode(Fields.self, from: json)
        self.json = json
        self.recipe = fields.recipe ?? ""
        self.bytes = try Data.fromNativeHex(fields.secretBytes, field: "secretBytes")
    }

    public static func deriveFromSeed(withSeedString seedString: String, recipe: String) throws -> Secret {
        try Secret(nativeJson: Native.string { out, err in dkc_secret_derive(seedString, recipe, out, err) })
    }

    public static func from(json: String) throws -> Secret {
        try Secret(nativeJson: Native.string { out, err in dkc_secret_from_json(json, out, err) })
    }

    public func secretBytes() -> Data { bytes }

    public func toJson() -> String { json }
}
