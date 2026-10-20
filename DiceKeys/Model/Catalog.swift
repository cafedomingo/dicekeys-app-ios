//
//  Catalog.swift
//  DiceKeys
//
//  What the user has made, and nothing that unlocks it: DiceKeys by their one-way id, and
//  the kind, name and style of each key, which is everything needed to derive it again. It
//  can sync through the user's private CloudKit database, so every attribute has a default
//  and none is unique, as CloudKit requires.
//

import Derivation
import Foundation
import KeyFormats
import SwiftData

/// A DiceKey the app has seen, matched on every scan by its id.
@Model
final class DiceKeyRecord {
    var diceKeyID = ""
    var name = ""
    /// The center face in human-readable form, such as `M1t`: the DiceKey's avatar.
    var centerFace = ""
    var created = Date.now

    init(diceKey: DiceKey) {
        diceKeyID = diceKey.id
        centerFace = diceKey.centerFace.humanReadableForm
        name = diceKey.defaultName
    }

    /// What a cleared rename returns to.
    var defaultName: String { DiceKey.defaultName(centerFace: centerFace) }
}

/// A key the user made. Deriving it again needs only this and the DiceKey.
@Model
final class KeyEntry {
    var diceKeyID = ""
    var kind = KeyKind.ssh.rawValue
    var name = ""
    /// A passphrase's `PassphraseStyle`, JSON-encoded; nil for other kinds.
    var style: Data?
    /// Recorded to show and compare by eye, never checked.
    var publicKey: String?
    var created = Date.now

    init(diceKeyID: String, recipe: KeyRecipe, publicKey: String?) {
        self.diceKeyID = diceKeyID
        kind = recipe.kind.rawValue
        name = recipe.name
        style = recipe.style.flatMap { try? JSONEncoder().encode($0) }
        self.publicKey = publicKey
    }

    /// Nil for an entry a later version wrote, with a kind or a passphrase style this one
    /// can't read: guessing would show a different key as if it were this one.
    var recipe: KeyRecipe? {
        guard let kind = KeyKind(rawValue: kind) else { return nil }
        guard kind == .passphrase else { return try? KeyRecipe(kind: kind, name: name) }
        guard let style, let decoded = try? JSONDecoder().decode(PassphraseStyle.self, from: style) else { return nil }
        return try? KeyRecipe(kind: kind, name: name, style: decoded)
    }
}

enum Catalog {
    static let syncSettingKey = "syncsCatalogWithICloud"
    /// The setting as the app launched. The store opens once per launch, because two
    /// CloudKit mirrors on one store file aren't supported, so a change applies at the next.
    static let syncsThisLaunch = UserDefaults.standard.bool(forKey: syncSettingKey)
    private static let storeName = "Catalog"

    /// The same store file either way, so turning sync on or off keeps what is there.
    /// `.automatic` syncs through the iCloud container in the entitlements.
    static func container(syncing: Bool = syncsThisLaunch, inMemory: Bool = false) throws -> ModelContainer {
        let configuration = ModelConfiguration(
            storeName, isStoredInMemoryOnly: inMemory, cloudKitDatabase: syncing ? .automatic : .none)
        return try ModelContainer(for: DiceKeyRecord.self, KeyEntry.self, configurations: configuration)
    }
}

extension ModelContext {
    func record(for diceKeyID: String) throws -> DiceKeyRecord? {
        try records(for: diceKeyID).uniqueDiceKeys.first
    }

    private func records(for diceKeyID: String) throws -> [DiceKeyRecord] {
        try fetch(FetchDescriptor<DiceKeyRecord>(predicate: #Predicate { $0.diceKeyID == diceKeyID }))
    }

    func entries(for diceKeyID: String) throws -> [KeyEntry] {
        try fetch(
            FetchDescriptor<KeyEntry>(
                predicate: #Predicate { $0.diceKeyID == diceKeyID },
                sortBy: [SortDescriptor(\.name), SortDescriptor(\.created)])
        ).uniqueKeys
    }

    /// Records the DiceKey on first sight.
    func recordIfNew(_ diceKey: DiceKey) throws {
        guard try record(for: diceKey.id) == nil else { return }
        insert(DiceKeyRecord(diceKey: diceKey))
        try save()
    }

    /// The entry for this key, added if it isn't there yet, and saved so its id is final.
    @discardableResult
    func addEntry(for key: DerivedKey, diceKeyID: String) throws -> KeyEntry {
        if let existing = try entries(for: diceKeyID).first(where: { $0.recipe == key.recipe }) { return existing }
        let entry = KeyEntry(diceKeyID: diceKeyID, recipe: key.recipe, publicKey: key.publicKey)
        insert(entry)
        try save()
        return entry
    }

    /// Every entry for this key, including copies two devices made before they synced.
    func deleteKey(_ recipe: KeyRecipe, diceKeyID: String) throws {
        let all = try fetch(FetchDescriptor<KeyEntry>(predicate: #Predicate { $0.diceKeyID == diceKeyID }))
        for copy in all where copy.recipe == recipe { delete(copy) }
        try save()
    }

    /// The record, any copies a sync made, and its entries; the keychain copy is the caller's.
    func forget(_ record: DiceKeyRecord) throws {
        let diceKeyID = record.diceKeyID
        try delete(model: KeyEntry.self, where: #Predicate { $0.diceKeyID == diceKeyID })
        for copy in try records(for: diceKeyID) { delete(copy) }
        try save()
    }
}

extension [DiceKeyRecord] {
    /// Two devices that each scan a DiceKey before they sync make a record each. One stands
    /// for the DiceKey: a renamed one over one still named for its center die, then the
    /// oldest, so the choice is the same on every device. Order is kept.
    var uniqueDiceKeys: [DiceKeyRecord] {
        let chosen = Dictionary(grouping: self, by: \.diceKeyID).compactMapValues { copies in
            copies.min { ($0.isRenamed ? 0 : 1, $0.created) < ($1.isRenamed ? 0 : 1, $1.created) }
        }
        return filter { chosen[$0.diceKeyID] === $0 }
    }
}

extension DiceKeyRecord {
    fileprivate var isRenamed: Bool { name != defaultName }
}

extension [KeyEntry] {
    /// Two devices can make the same key before they sync, so entries are told apart by
    /// what they derive, not by row. Entries this version can't read are left out.
    var uniqueKeys: [KeyEntry] {
        var seen = Set<KeyRecipe>()
        return filter { entry in entry.recipe.map { seen.insert($0).inserted } ?? false }
    }
}
