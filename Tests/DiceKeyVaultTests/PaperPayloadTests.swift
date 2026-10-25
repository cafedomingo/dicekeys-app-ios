//
//  PaperPayloadTests.swift
//  DiceKeyVaultTests
//

import Derivation
import Foundation
import Testing

@testable import DiceKeyVault

struct PaperPayloadTests {
    private static let item = CatalogFile.DiceKeyItem(
        id: DiceKey.example.id, name: "Example", centerFace: DiceKey.example.centerFace.text)

    private static func catalog(publicKey: String? = nil) throws -> CatalogFile {
        let recipes = [
            try KeyRecipe(kind: .ssh, name: "🧨 & 日本語"),
            try KeyRecipe(kind: .age, name: #"quote " and \ مفتاح"#),
            try KeyRecipe(kind: .ssh, name: "github"),
            try KeyRecipe(kind: .passphrase, name: "bank", style: .memorable(words: 6, digitsAndUppercase: true)),
            try KeyRecipe(kind: .passphrase, name: "nas", style: .random(length: 24, symbols: false))
        ]
        return CatalogFile(
            diceKeys: [item],
            keys: recipes.map { CatalogFile.KeyItem(diceKey: DiceKey.example.id, recipe: $0, publicKey: publicKey) })
    }

    private func payload(_ json: String) throws -> String {
        try PaperPayload.pack(Data(json.utf8))
    }

    private func payload(name: String, keys: String = "") throws -> String {
        try payload(
            #"{"centerFace":"M1t","id":"\#(DiceKey.example.id)","keys":[\#(keys)],"name":"\#(name)","v":2}"#)
    }

    private func ssh(_ names: some Sequence<String>) -> String {
        names.map { #"{"kind":"ssh","name":"\#($0)"}"# }.joined(separator: ",")
    }

    @Test("a catalog and its faces come back as they went in")
    func roundTrip() throws {
        let catalog = try Self.catalog()
        let decoded = try PaperPayload.decode(PaperPayload.encode(catalog))
        #expect(decoded.catalog == catalog)
        #expect(decoded.faces == nil)
    }

    @Test("the faces travel with the list when given")
    func roundTripWithFaces() throws {
        let catalog = try Self.catalog()
        let decoded = try PaperPayload.decode(PaperPayload.encode(catalog, faces: DiceKey.example.text))
        #expect(decoded.catalog == catalog)
        #expect(decoded.faces == DiceKey.example.text)
    }

    @Test("the payload is compact sorted JSON of the DiceKey and each key's recipe fields alone")
    func keysCarryOnlyRecipeFields() throws {
        let catalog = try Self.catalog(publicKey: "public")
        let text = try PaperPayload.encode(catalog)
        let json = try PaperPayload.unpack(text)
        #expect(String(decoding: json, as: UTF8.self).hasPrefix(#"{"centerFace":"M1t","id":""#))
        let object = try #require(try JSONSerialization.jsonObject(with: json) as? [String: Any])
        #expect(Set(object.keys) == ["centerFace", "id", "keys", "name", "v"])
        #expect(object["v"] as? Int == 2)
        let keys = try #require(object["keys"] as? [[String: Any]])
        #expect(keys.count == catalog.keys.count)
        for key in keys {
            #expect(key["diceKey"] == nil)
            #expect(key["publicKey"] == nil)
        }
        let withFaces = try PaperPayload.unpack(PaperPayload.encode(catalog, faces: DiceKey.example.text))
        let faces = try #require(try JSONSerialization.jsonObject(with: withFaces) as? [String: Any])
        #expect(Set(faces.keys) == ["centerFace", "diceKey", "id", "keys", "name", "v"])
    }

    @Test("a stream of stored blocks, with no zlib header, is read as raw DEFLATE")
    func rawDeflate() throws {
        let stored: [UInt8] = [0x01, 0x05, 0x00, 0xFA, 0xFF] + Array("hello".utf8)
        #expect(try PaperPayload.unpack(Data(stored).base64URLEncodedString) == Data("hello".utf8))
    }

    @Test("a key with a field this version doesn't know is skipped and counted")
    func unknownFieldSkipsKey() throws {
        let keys = #"{"kind":"ssh","name":"a","extra":1},{"kind":"ssh","name":"b"}"#
        let decoded = try PaperPayload.decode(payload(name: "Example", keys: keys)).catalog
        #expect(decoded.keys.map(\.recipe.name) == ["b"])
        #expect(decoded.keys.map(\.diceKey) == [DiceKey.example.id])
        #expect(decoded.unreadableKeys == 1)
    }

    @Test("a newer version says to update, whatever else it holds")
    func newerVersionRefused() throws {
        let text = try payload(#"{"future":true,"v":3}"#)
        #expect(throws: CatalogFile.Failure.newerVersion(3)) { try PaperPayload.decode(text) }
    }

    @Test("text that isn't a version 2 payload is refused as not a catalog")
    func garbageRefused() throws {
        let truncated = try PaperPayload.encode(Self.catalog()).dropLast(8)
        let texts = [
            "",
            "!!",
            String(truncated),
            Data("not deflate".utf8).base64URLEncodedString,
            try payload("not json"),
            try payload(#"{"v":1}"#),
            try payload(#"{"v":2}"#)
        ]
        for text in texts {
            #expect(throws: CatalogFile.Failure.notACatalog) { try PaperPayload.decode(text) }
        }
    }

    @Test("more than 1,000 items is refused, counting the DiceKey and every key")
    func tooManyItemsRefused() throws {
        let name = "Example"
        let atTheLimit = try payload(name: name, keys: ssh((1..<CatalogFile.maximumItems).map { "k\($0)" }))
        #expect(try PaperPayload.decode(atTheLimit).catalog.keys.count == CatalogFile.maximumItems - 1)
        let over = try payload(name: name, keys: ssh((0..<CatalogFile.maximumItems).map { "k\($0)" }))
        #expect(throws: CatalogFile.Failure.notACatalog) { try PaperPayload.decode(over) }
    }

    @Test("a payload that inflates past the cap is refused")
    func oversizedRefused() throws {
        let allowed = try payload(name: String(repeating: " ", count: PaperPayload.maximumUnpackedBytes / 2))
        #expect(try PaperPayload.decode(allowed).catalog.diceKeys.count == 1)
        let oversized = try payload(name: String(repeating: " ", count: 300 * 1024))
        #expect(throws: CatalogFile.Failure.notACatalog) { try PaperPayload.decode(oversized) }
    }

    @Test("only a catalog of exactly one DiceKey can be written")
    func encodeNeedsOneDiceKey() throws {
        let two = CatalogFile(diceKeys: [Self.item, Self.item], keys: [])
        #expect(throws: CatalogFile.Failure.notACatalog) { try PaperPayload.encode(two) }
        let none = CatalogFile(diceKeys: [], keys: [])
        #expect(throws: CatalogFile.Failure.notACatalog) { try PaperPayload.encode(none) }
    }
}
