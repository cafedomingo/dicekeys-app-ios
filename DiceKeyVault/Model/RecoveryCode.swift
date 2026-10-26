//
//  RecoveryCode.swift
//  DiceKeyVault
//

import SwiftData

/// A DiceKey and its list, as the recovery sheet's code: text the app recognizes by its
/// prefix, never a link, so the faces don't pass through link handling. The format is in
/// `docs/catalog-format.md`.
struct RecoveryCode: Equatable {
    static let prefix = "DKVR:"

    let diceKey: DiceKey
    /// Exactly one DiceKey, this one, and its keys without public keys.
    let catalog: CatalogFile

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
        guard payload.hasPrefix(Self.prefix) else { throw CatalogFile.Failure.notACatalog }
        let (catalog, faces) = try PaperPayload.decode(String(payload.dropFirst(Self.prefix.count)))
        guard let faces, let diceKey = try? DiceKey(text: faces), catalog.diceKeys[0].id == diceKey.id else {
            throw CatalogFile.Failure.notACatalog
        }
        self.diceKey = diceKey
        self.catalog = catalog
    }

    var payload: String {
        get throws { Self.prefix + (try PaperPayload.encode(catalog, faces: diceKey.text)) }
    }

    /// Merges the list, adding only what is missing, and returns the DiceKey to unlock.
    @discardableResult
    func restore(into context: ModelContext) throws -> DiceKey {
        try catalog.merge(into: context)
        return diceKey
    }
}
