//
//  CatalogFile.swift
//  DiceKeys
//

import Derivation
import Foundation
import SwiftData

/// The catalog as a file, for export, import and the paper copy's QR code: everything
/// needed to make each key again, and nothing that unlocks one.
struct CatalogFile: Codable, Equatable {
    static let version = 1
    /// The QR code carries the file in a URL the Camera app opens in this app.
    static let urlScheme = "dicekeyvault"
    private static let importHost = "import"
    private static let fileItem = "catalog"

    struct DiceKeyItem: Codable, Equatable {
        let id: String
        let name: String
        let centerFace: String
    }

    /// A key is its recipe's own fields, the same as the hashed text, plus which DiceKey it
    /// belongs to.
    struct KeyItem: Codable, Hashable {
        let diceKey: String
        let recipe: KeyRecipe
        /// For reading in the file. Never imported: a file could carry anyone's key, so an
        /// entry's public key only ever comes from deriving it here.
        var publicKey: String?

        init(diceKey: String, recipe: KeyRecipe, publicKey: String? = nil) {
            self.diceKey = diceKey
            self.recipe = recipe
            self.publicKey = publicKey
        }
    }

    /// Far more than anyone makes, and small enough that a crafted file can't stall the app.
    static let maximumItems = 1000

    enum Failure: LocalizedError, Equatable {
        case notACatalog
        case newerVersion(Int)

        var errorDescription: String? {
            switch self {
            case .notACatalog: "This isn't a list of \(AppInfo.name) keys, or part of it is missing."
            case .newerVersion: "This was made by a newer version of \(AppInfo.name). Update the app to read it."
            }
        }
    }

    var v = Self.version
    var diceKeys: [DiceKeyItem]
    var keys: [KeyItem]
    /// Keys in the file this version can't read, such as a kind a later version added: each
    /// is left out rather than refusing paper that holds the rest.
    private(set) var unreadableKeys = 0

    private enum CodingKeys: CodingKey {
        case v, diceKeys, keys
    }

    /// Reads each key on its own, so one this version doesn't know leaves the rest.
    private struct Readable<Value: Decodable>: Decodable {
        let value: Value?

        init(from decoder: any Decoder) throws {
            value = try? Value(from: decoder)
        }
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        v = try container.decode(Int.self, forKey: .v)
        diceKeys = try container.decode([DiceKeyItem].self, forKey: .diceKeys)
        let read = try container.decode([Readable<KeyItem>].self, forKey: .keys)
        keys = read.compactMap(\.value)
        unreadableKeys = read.count - keys.count
    }

    init(diceKeys: [DiceKeyItem], keys: [KeyItem]) {
        self.diceKeys = diceKeys
        self.keys = keys
    }

    init(records: [DiceKeyRecord], entries: [KeyEntry]) {
        diceKeys = records.map { DiceKeyItem(id: $0.diceKeyID, name: $0.name, centerFace: $0.centerFace) }
        keys = entries.uniqueKeys.compactMap { entry in
            entry.recipe.map { KeyItem(diceKey: entry.diceKeyID, recipe: $0, publicKey: entry.publicKey) }
        }
    }

    init(json: Data) throws {
        let file: CatalogFile
        do {
            file = try JSONDecoder().decode(CatalogFile.self, from: json)
        } catch {
            throw Failure.notACatalog
        }
        guard file.v <= Self.version else { throw Failure.newerVersion(file.v) }
        guard file.diceKeys.count + file.keys.count <= Self.maximumItems else { throw Failure.notACatalog }
        self = file
    }

    init(importURL url: URL) throws {
        guard url.scheme == Self.urlScheme, url.host() == Self.importHost,
            let item = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?
                .first(where: { $0.name == Self.fileItem })?.value,
            let json = Data(base64URLEncoded: item)
        else { throw Failure.notACatalog }
        try self.init(json: json)
    }

    /// Readable for a file someone keeps themselves; compact for the QR code.
    func json(readable: Bool = true) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = readable ? [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes] : [.sortedKeys]
        return try encoder.encode(self)
    }

    var importURL: URL {
        get throws {
            var compact = self
            compact.keys = keys.map {
                var key = $0
                key.publicKey = nil
                return key
            }
            var components = URLComponents()
            components.scheme = Self.urlScheme
            components.host = Self.importHost
            components.queryItems = [
                URLQueryItem(name: Self.fileItem, value: try compact.json(readable: false).base64URLEncodedString)
            ]
            guard let url = components.url else { throw URLError(.badURL) }
            return url
        }
    }

    /// Adds what the catalog doesn't have yet, matching DiceKeys by id and keys by what they
    /// derive. Keys that can't be made again here (no DiceKey for them, or a recipe this version
    /// refuses or can't read) are counted as unreadable, never dropped silently.
    @discardableResult
    func merge(into context: ModelContext) throws -> (diceKeys: Int, keys: Int, unreadable: Int) {
        var added = (diceKeys: 0, keys: 0, unreadable: unreadableKeys)
        for item in diceKeys where try context.record(for: item.id) == nil {
            let name = (try? KeyRecipe.normalizedName(item.name)) ?? DiceKey.defaultName(centerFace: item.centerFace)
            context.insert(DiceKeyRecord(diceKeyID: item.id, name: name, centerFace: item.centerFace))
            added.diceKeys += 1
        }
        for item in keys {
            guard try context.record(for: item.diceKey) != nil else {
                added.unreadable += 1
                continue
            }
            guard try !context.entries(for: item.diceKey).contains(where: { $0.recipe == item.recipe }) else {
                continue
            }
            context.insert(KeyEntry(diceKeyID: item.diceKey, recipe: item.recipe, publicKey: nil))
            added.keys += 1
        }
        try context.save()
        return added
    }
}

extension CatalogFile.KeyItem {
    private enum CodingKeys: String, CodingKey {
        case diceKey, publicKey
    }

    /// Any field that is neither the catalog's nor the recipe's, such as one a later version
    /// adds to recipes, makes the key unreadable rather than read as a different recipe.
    private struct AnyKey: CodingKey {
        let stringValue: String
        var intValue: Int? { nil }
        init(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { nil }
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        diceKey = try container.decode(String.self, forKey: .diceKey)
        publicKey = try container.decodeIfPresent(String.self, forKey: .publicKey)
        recipe = try KeyRecipe(from: decoder)
        let catalogKeys = Set([CodingKeys.diceKey, .publicKey].map(\.stringValue))
        let fields = try decoder.container(keyedBy: AnyKey.self).allKeys.map(\.stringValue)
        guard Set(fields).subtracting(catalogKeys) == Set(recipe.fieldNames) else {
            throw CatalogFile.Failure.notACatalog
        }
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(diceKey, forKey: .diceKey)
        try container.encodeIfPresent(publicKey, forKey: .publicKey)
        try recipe.encode(to: encoder)
    }
}
