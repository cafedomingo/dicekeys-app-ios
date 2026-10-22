//
//  RecoveryCode.swift
//  DiceKeys
//

import Derivation
import Foundation
import SwiftData

/// A DiceKey and its list, as the recovery sheet's code: text the app recognizes by its
/// prefix, never a link, so the faces don't pass through link handling. The format is in
/// `docs/catalog-format.md`.
struct RecoveryCode: Equatable {
    static let prefix = "DKV1R:"

    let diceKey: DiceKey
    /// Exactly one DiceKey, this one, and its keys without public keys.
    let catalog: CatalogFile

    private struct Wire: Encodable {
        // Read only by the synthesized encoder.
        // swiftlint:disable:next unused_declaration
        var v = CatalogFile.version
        let diceKey: String
        let diceKeys: [CatalogFile.DiceKeyItem]
        let keys: [CatalogFile.KeyItem]
    }

    /// The faces alone; the rest reads as a catalog file, key by key.
    private struct Faces: Decodable {
        let diceKey: String
    }

    init(diceKey: DiceKey, record: DiceKeyRecord, entries: [KeyEntry]) {
        self.diceKey = diceKey
        var catalog = CatalogFile(records: [record], entries: entries)
        catalog.keys = catalog.keys.map {
            var key = $0
            key.publicKey = nil
            return key
        }
        self.catalog = catalog
    }

    init(payload: String) throws {
        guard payload.hasPrefix(Self.prefix),
            let json = Data(base64URLEncoded: String(payload.dropFirst(Self.prefix.count)))
        else { throw CatalogFile.Failure.notACatalog }
        let catalog = try CatalogFile(json: json)
        guard let faces = try? JSONDecoder().decode(Faces.self, from: json),
            let diceKey = try? DiceKey(humanReadableForm: faces.diceKey), catalog.diceKeys.count == 1,
            catalog.diceKeys[0].id == diceKey.id, catalog.keys.allSatisfy({ $0.diceKey == diceKey.id })
        else { throw CatalogFile.Failure.notACatalog }
        self.diceKey = diceKey
        self.catalog = catalog
    }

    var payload: String {
        get throws {
            let encoder = JSONEncoder()
            encoder.outputFormatting = .sortedKeys
            let wire = Wire(diceKey: diceKey.humanReadableForm, diceKeys: catalog.diceKeys, keys: catalog.keys)
            return Self.prefix + (try encoder.encode(wire)).base64URLEncodedString
        }
    }

    /// Merges the list, adding only what is missing, and returns the DiceKey to unlock.
    @discardableResult
    func restore(into context: ModelContext) throws -> DiceKey {
        try catalog.merge(into: context)
        return diceKey
    }
}
