//
//  Catalog.swift
//  DiceKeys
//
//  What the user has made, and nothing that unlocks it: DiceKeys by their one-way id, and
//  the kind, name and style of each key, which is everything needed to derive it again. It
//  can sync through the user's private CloudKit database. Every attribute has a default and
//  none is unique, as CloudKit requires.
//

// The app calls into this only from the rebuild that follows, so nothing references it yet.
// swiftlint:disable unused_declaration

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
        name = nicknameForDiceKey(centerFace: diceKey.centerFace)
    }
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
    static let cloudKitContainer = "iCloud.com.cafedomingo.dicekeys"
    static let syncSettingKey = "syncCatalogWithICloud"

    /// The same store file either way, so turning sync on or off keeps what is there.
    static func container(syncing: Bool, inMemory: Bool = false) throws -> ModelContainer {
        let configuration = ModelConfiguration(
            "Catalog",
            isStoredInMemoryOnly: inMemory,
            cloudKitDatabase: syncing ? .private(cloudKitContainer) : .none)
        return try ModelContainer(for: DiceKeyRecord.self, KeyEntry.self, configurations: configuration)
    }
}

extension ModelContext {
    func record(for diceKeyID: String) throws -> DiceKeyRecord? {
        try fetch(FetchDescriptor<DiceKeyRecord>(predicate: #Predicate { $0.diceKeyID == diceKeyID })).first
    }

    /// Two devices can make the same key before they sync, so entries are told apart by
    /// what they derive, not by row.
    func entries(for diceKeyID: String) throws -> [KeyEntry] {
        let all = try fetch(
            FetchDescriptor<KeyEntry>(
                predicate: #Predicate { $0.diceKeyID == diceKeyID },
                sortBy: [SortDescriptor(\.name), SortDescriptor(\.created)]))
        var seen = Set<KeyRecipe>()
        return all.filter { entry in entry.recipe.map { seen.insert($0).inserted } ?? false }
    }

    /// Records the DiceKey on first sight. Returns whether it was already known.
    @discardableResult
    func recognize(_ diceKey: DiceKey) throws -> Bool {
        if try record(for: diceKey.id) != nil { return true }
        insert(DiceKeyRecord(diceKey: diceKey))
        return false
    }

    /// Saves a key unless the same one is already there.
    func save(_ key: DerivedKey, for diceKeyID: String) throws {
        if try entries(for: diceKeyID).contains(where: { $0.recipe == key.recipe }) { return }
        insert(KeyEntry(diceKeyID: diceKeyID, recipe: key.recipe, publicKey: key.publicKey))
    }
}

// swiftlint:enable unused_declaration
