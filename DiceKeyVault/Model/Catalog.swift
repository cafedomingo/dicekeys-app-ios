//
//  Catalog.swift
//  DiceKeyVault
//
//  What the user has made, and nothing that unlocks it: DiceKeys by their one-way id, and
//  each key's recipe, which is everything needed to derive it again. It
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
    /// The center face as text, such as `M1t`: the DiceKey's avatar.
    var centerFace = ""
    var created = Date.now

    init(diceKeyID: String, name: String, centerFace: String) {
        self.diceKeyID = diceKeyID
        self.name = name
        self.centerFace = centerFace
    }

    convenience init(diceKey: DiceKey) {
        self.init(diceKeyID: diceKey.id, name: diceKey.defaultName, centerFace: diceKey.centerFace.text)
    }

    /// What a cleared rename returns to.
    var defaultName: String { DiceKey.defaultName(centerFace: centerFace) }
}

/// A key the user made. Deriving it again needs only this and the DiceKey.
@Model
final class KeyEntry {
    var diceKeyID = ""
    /// The recipe's canonical text, the bytes its key was derived from, so no Swift type
    /// shapes what is stored or synced.
    var recipeJSON = ""
    /// Each algorithm's public key, by its type's raw value: `["x25519": "age1…",
    /// "mlkem768x25519": "age1pq1…"]`. Recorded to show and compare by eye, never checked.
    /// Keyed by String, not `DerivableType`, so a name this version doesn't know, from a newer
    /// version on another device, is kept when this version writes, not dropped. Never filter
    /// on it in a `#Predicate`: SwiftData crashes.
    var publicKeys: [String: String] = [:]
    var created = Date.now

    init(diceKeyID: String, recipe: KeyRecipe, publicKeys: [String: String] = [:]) {
        self.diceKeyID = diceKeyID
        recipeJSON = recipe.json
        self.publicKeys = publicKeys
    }

    /// Nil for an entry this version can't read, such as a kind or field a later version wrote,
    /// where guessing would show a different key as if it were this one.
    var recipe: KeyRecipe? { try? KeyRecipe(json: recipeJSON) }

    /// The public key recorded for this algorithm, if any.
    func publicKey(for type: DerivableType) -> String? { publicKeys[type.rawValue] }

    /// Its kind has a public half and some algorithm's public key isn't recorded yet, which
    /// its DiceKey fills in once unlocked.
    var needsPublicKey: Bool {
        guard let kind = recipe?.kind, kind.hasPublicKey else { return false }
        return kind.algorithms.contains { publicKey(for: $0) == nil }
    }
}

enum Catalog {
    static let syncSettingKey = "syncsCatalogWithICloud"
    /// The setting as the app launched. The store opens once per launch, because two
    /// CloudKit mirrors on one store file aren't supported, so a change applies at the next.
    static let syncsThisLaunch = UserDefaults.standard.bool(forKey: syncSettingKey)
    static let storeName = "Catalog"

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
        try allEntries(for: diceKeyID).uniqueKeys
    }

    /// Every row, including copies two devices made before they synced.
    private func allEntries(for diceKeyID: String) throws -> [KeyEntry] {
        try fetch(FetchDescriptor<KeyEntry>(predicate: #Predicate { $0.diceKeyID == diceKeyID }))
    }

    /// Records the DiceKey, with its default keys, on first sight; true when it did.
    @discardableResult
    func recordIfNew(_ diceKey: DiceKey) throws -> Bool {
        guard try record(for: diceKey.id) == nil else { return false }
        insert(DiceKeyRecord(diceKey: diceKey))
        try addMissingDefaults(for: diceKey.id)
        try save()
        return true
    }

    /// Adds each default key the DiceKey doesn't have yet, for the caller to save, so a default
    /// a later version adds reaches DiceKeys recorded before it. They have no public keys yet:
    /// the seed may not be here, and `fillPublicKeys` fills them in once the DiceKey is unlocked.
    func addMissingDefaults(for diceKeyID: String) throws {
        let recorded = Set(try entries(for: diceKeyID).compactMap(\.recipe))
        for recipe in KeyRecipe.defaults where !recorded.contains(recipe) {
            insert(KeyEntry(diceKeyID: diceKeyID, recipe: recipe))
        }
    }

    /// For DiceKeys recorded before a default existed, and records a sync brings.
    func addMissingDefaults() throws {
        for record in try fetch(FetchDescriptor<DiceKeyRecord>()) {
            try addMissingDefaults(for: record.diceKeyID)
        }
        try save()
    }

    func entry(for recipe: KeyRecipe, diceKeyID: String) throws -> KeyEntry? {
        try entries(for: diceKeyID).first { $0.recipe == recipe }
    }

    /// The entry for this key, added if it isn't there yet, and saved so its id is final.
    @discardableResult
    func addEntry(for key: DerivedKey, diceKeyID: String) throws -> KeyEntry {
        if let existing = try entry(for: key.recipe, diceKeyID: diceKeyID) { return existing }
        let entry = KeyEntry(diceKeyID: diceKeyID, recipe: key.recipe, publicKeys: key.publicKeys)
        insert(entry)
        try save()
        return entry
    }

    /// Fills in, from the DiceKey itself, every public key a key is recorded without: a
    /// default's, an imported key's, or one for an algorithm added since the key was recorded,
    /// in every copy a sync made. Each missing one is set on its own, never the whole map, so a
    /// name this version doesn't know stays.
    func fillPublicKeys(for diceKey: DiceKey) throws {
        let missing = try allEntries(for: diceKey.id).filter(\.needsPublicKey)
        for entry in missing {
            guard let recipe = entry.recipe else { continue }
            let derived = DerivedKey.derive(seed: diceKey.seed, recipe: recipe).publicKeys
            for type in recipe.kind.algorithms where entry.publicKey(for: type) == nil {
                entry.publicKeys[type.rawValue] = derived[type.rawValue]
            }
        }
        if !missing.isEmpty { try save() }
    }

    /// Every entry for this key, including copies two devices made before they synced.
    func deleteKey(_ recipe: KeyRecipe, diceKeyID: String) throws {
        for copy in try allEntries(for: diceKeyID) where copy.recipe == recipe { delete(copy) }
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
    /// oldest, then by name, so the choice is the same on every device. Order is kept.
    var uniqueDiceKeys: [DiceKeyRecord] {
        let chosen = Dictionary(grouping: self, by: \.diceKeyID).compactMapValues { copies in
            copies.min {
                ($0.isRenamed ? 0 : 1, $0.created, $0.name) < ($1.isRenamed ? 0 : 1, $1.created, $1.name)
            }
        }
        return filter { chosen[$0.diceKeyID] === $0 }
    }
}

extension DiceKeyRecord {
    fileprivate var isRenamed: Bool { name != defaultName }
}

extension KeyRecipe {
    fileprivate var defaultRank: Int { Self.defaults.firstIndex(of: self) ?? Self.defaults.count }
}

extension [KeyEntry] {
    /// The rows the public key fill has work for: those whose DiceKey is unlocked, and that
    /// miss a public key. Checked in code, since the map can't be filtered in the store, and
    /// the DiceKey first, since it is cheap and nothing caps the store's rows, while
    /// `needsPublicKey` decodes the recipe.
    func keysToFill(isUnlocked: (String) -> Bool) -> Set<PersistentIdentifier> {
        Set(filter { isUnlocked($0.diceKeyID) && $0.needsPublicKey }.map(\.persistentModelID))
    }

    /// Two devices can make the same key before they sync, so entries are told apart by
    /// DiceKey and recipe, not by row, and the oldest copy stands for the key. Entries this
    /// version can't read are left out. The default keys come first, in their own order, then
    /// the rest by name and age: the name is only in the recipe text, which the store can't
    /// sort by.
    var uniqueKeys: [KeyEntry] {
        var seen = [String: Set<KeyRecipe>]()
        return compactMap { entry in entry.recipe.map { (entry: entry, recipe: $0) } }
            .sorted { lhs, rhs in
                if lhs.recipe.defaultRank != rhs.recipe.defaultRank {
                    return lhs.recipe.defaultRank < rhs.recipe.defaultRank
                }
                return switch (lhs.recipe.name ?? "").localizedStandardCompare(rhs.recipe.name ?? "") {
                case .orderedAscending: true
                case .orderedDescending: false
                case .orderedSame: lhs.entry.created < rhs.entry.created
                }
            }
            .filter { seen[$0.entry.diceKeyID, default: []].insert($0.recipe).inserted }
            .map(\.entry)
    }
}
