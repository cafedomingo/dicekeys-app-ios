//
//  PaperPayload.swift
//  DiceKeyVault
//

import Compression
import Derivation
import Foundation

/// One DiceKey's list as both paper codes carry it: compact JSON, raw DEFLATE, base64url.
enum PaperPayload {
    static let version = 2
    /// Far above what a paper code inflates to, and small enough that a crafted code can't stall the app.
    static let maximumUnpackedBytes = 256 * 1024
    private static let readChunkBytes = 16 * 1024

    private struct Wire: Encodable {
        // Read only by the synthesized encoder.
        // swiftlint:disable:next unused_declaration
        var v = PaperPayload.version
        let id: String
        let name: String
        let centerFace: String
        let keys: [KeyRecipe]
        let diceKey: String?
    }

    private struct Version: Decodable {
        let v: Int
    }

    private struct Body: Decodable {
        let id: String
        let name: String
        let centerFace: String
        let keys: [CatalogFile.Readable<Key>]
        let diceKey: String?
    }

    private struct Key: Decodable {
        let recipe: KeyRecipe

        init(from decoder: any Decoder) throws {
            recipe = try KeyRecipe(from: decoder, besides: [])
        }
    }

    /// `catalog` holds exactly one DiceKey and only its keys; public keys are left out.
    /// Throws `CatalogFile.Failure.notACatalog` for any other number of DiceKeys.
    static func encode(_ catalog: CatalogFile, faces: String? = nil) throws -> String {
        guard catalog.diceKeys.count == 1, let item = catalog.diceKeys.first else {
            throw CatalogFile.Failure.notACatalog
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        let wire = Wire(
            id: item.id, name: item.name, centerFace: item.centerFace, keys: catalog.keys.map(\.recipe),
            diceKey: faces)
        return try pack(encoder.encode(wire))
    }

    static func decode(_ text: String) throws -> (catalog: CatalogFile, faces: String?) {
        let json = try unpack(text)
        let decoder = JSONDecoder()
        guard let found = try? decoder.decode(Version.self, from: json).v else {
            throw CatalogFile.Failure.notACatalog
        }
        guard found <= version else { throw CatalogFile.Failure.newerVersion(found) }
        guard found == version, let body = try? decoder.decode(Body.self, from: json),
            1 + body.keys.count <= CatalogFile.maximumItems
        else { throw CatalogFile.Failure.notACatalog }
        let keys = body.keys.compactMap(\.value).map { CatalogFile.KeyItem(diceKey: body.id, recipe: $0.recipe) }
        let catalog = CatalogFile(
            diceKeys: [CatalogFile.DiceKeyItem(id: body.id, name: body.name, centerFace: body.centerFace)],
            keys: keys, unreadableKeys: body.keys.count - keys.count)
        return (catalog, body.diceKey)
    }

    /// The compression and text layers alone: `encode` ends with them, and tests use them to write a payload by hand.
    static func pack(_ json: Data) throws -> String {
        (try (json as NSData).compressed(using: .zlib) as Data).base64URLEncodedString
    }

    /// Stops inflating as soon as the output passes the cap, since DEFLATE can inflate 1,000 to 1.
    static func unpack(_ text: String) throws -> Data {
        do {
            guard var input = Data(base64URLEncoded: text) else { throw CatalogFile.Failure.notACatalog }
            let filter = try InputFilter(.decompress, using: .zlib) { count in
                defer { input = input.dropFirst(count) }
                return input.isEmpty ? nil : input.prefix(count)
            }
            var json = Data()
            while let chunk = try filter.readData(ofLength: readChunkBytes), !chunk.isEmpty {
                json += chunk
                guard json.count <= maximumUnpackedBytes else { throw CatalogFile.Failure.notACatalog }
            }
            return json
        } catch {
            throw CatalogFile.Failure.notACatalog
        }
    }
}
