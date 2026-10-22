//
//  CatalogTests.swift
//  DiceKeysTests
//

import Derivation
import Foundation
import KeyFormats
import SwiftData
import Testing

@testable import DiceKeys

@MainActor
struct CatalogTests {
    private let context: ModelContext

    init() throws {
        context = ModelContext(try Catalog.container(syncing: false, inMemory: true))
    }

    private func key(_ kind: KeyKind, _ name: String, style: PassphraseStyle = .standard) throws -> DerivedKey {
        DerivedKey.derive(seed: DiceKey.example.seed, recipe: try KeyRecipe(kind: kind, name: name, style: style))
    }

    /// Two devices that each scanned the DiceKey before syncing hold a record each.
    private func syncedDuplicate(named name: String? = nil, created: Date) -> DiceKeyRecord {
        let record = DiceKeyRecord(diceKey: DiceKey.example)
        if let name { record.name = name }
        record.created = created
        context.insert(record)
        return record
    }

    @Test("records a sync duplicated show as one DiceKey, the renamed one over the default")
    func duplicateRecordsCollapse() throws {
        _ = syncedDuplicate(created: .distantPast)
        let renamed = syncedDuplicate(named: "Home box", created: .now)
        let records = try context.fetch(FetchDescriptor<DiceKeyRecord>())
        #expect(records.uniqueDiceKeys.map(\.persistentModelID) == [renamed.persistentModelID])
        #expect(try context.record(for: DiceKey.example.id)?.name == "Home box")
    }

    @Test("with both renamed, the older record is the DiceKey")
    func olderRenameWins() throws {
        _ = syncedDuplicate(named: "Office", created: .now)
        _ = syncedDuplicate(named: "Home box", created: .distantPast)
        #expect(try context.record(for: DiceKey.example.id)?.name == "Home box")
    }

    @Test("Forget removes every copy of the record, so none is left behind")
    func forgetRemovesDuplicates() throws {
        let first = syncedDuplicate(created: .distantPast)
        _ = syncedDuplicate(created: .now)
        try context.forget(first)
        #expect(try context.fetchCount(FetchDescriptor<DiceKeyRecord>()) == 0)
    }

    @Test("a DiceKey is recorded once, named by its center die")
    func recording() throws {
        try context.recordIfNew(DiceKey.example)
        try context.recordIfNew(DiceKey.example)
        #expect(try context.fetchCount(FetchDescriptor<DiceKeyRecord>()) == 1)
        let record = try #require(try context.record(for: DiceKey.example.id))
        #expect(record.name == "DiceKey with M1 in center")
        #expect(record.centerFace == DiceKey.example.centerFace.humanReadableForm)
    }

    @Test("an entry stores the recipe's canonical text and rebuilds it, sorted by name")
    func entryRoundTrip() throws {
        let style = PassphraseStyle.memorable(words: 7, digitsAndUppercase: true)
        let passphrase = try key(.passphrase, "nas", style: style)
        try context.addEntry(for: passphrase, diceKeyID: DiceKey.example.id)
        try context.addEntry(for: try key(.ssh, "github"), diceKeyID: DiceKey.example.id)
        let entries = try context.entries(for: DiceKey.example.id)
        #expect(entries.map(\.recipe?.name) == ["github", "nas"])
        #expect(entries[1].recipeJSON == passphrase.recipe.json)
        #expect(entries[1].recipe == passphrase.recipe)
        #expect(entries[1].publicKey == nil)
        #expect(entries[0].publicKey?.hasPrefix("ssh-ed25519 ") == true)
    }

    @Test("the same key saved twice, or synced from two devices, appears once")
    func duplicates() throws {
        let ssh = try key(.ssh, "github")
        try context.addEntry(for: ssh, diceKeyID: DiceKey.example.id)
        try context.addEntry(for: ssh, diceKeyID: DiceKey.example.id)
        context.insert(KeyEntry(diceKeyID: DiceKey.example.id, recipe: ssh.recipe, publicKey: ssh.publicKey))
        #expect(try context.entries(for: DiceKey.example.id).count == 1)
    }

    @Test("of two synced copies, the older stands for the key")
    func olderCopyWins() throws {
        let ssh = try key(.ssh, "github")
        let newer = KeyEntry(diceKeyID: DiceKey.example.id, recipe: ssh.recipe, publicKey: nil)
        newer.created = .now
        context.insert(newer)
        let older = KeyEntry(diceKeyID: DiceKey.example.id, recipe: ssh.recipe, publicKey: ssh.publicKey)
        older.created = .distantPast
        context.insert(older)
        #expect(try context.entries(for: DiceKey.example.id).map(\.persistentModelID) == [older.persistentModelID])
    }

    @Test(
        "an entry whose text isn't a recipe this version reads is left out, not guessed",
        arguments: [
            #"{"kind":"future","name":"backup"}"#,
            #"{"name":"backup","kind":"age"}"#,
            #"{"kind":"passphrase","length":6,"list":"eff_large_wordlist","name":"nas","separator":"future"}"#,
            ""
        ])
    func unreadableRecipe(_ text: String) throws {
        let entry = KeyEntry(diceKeyID: "x", recipe: try key(.age, "backup").recipe, publicKey: nil)
        entry.recipeJSON = text
        context.insert(entry)
        #expect(entry.recipe == nil)
        #expect(try context.entries(for: "x").isEmpty)
    }

    @Test("deleting a key removes its synced copies and leaves the other keys")
    func deletingAKey() throws {
        let github = try key(.ssh, "github")
        try context.addEntry(for: github, diceKeyID: DiceKey.example.id)
        context.insert(KeyEntry(diceKeyID: DiceKey.example.id, recipe: github.recipe, publicKey: github.publicKey))
        try context.addEntry(for: try key(.ssh, "homelab"), diceKeyID: DiceKey.example.id)
        try context.deleteKey(github.recipe, diceKeyID: DiceKey.example.id)
        #expect(try context.fetch(FetchDescriptor<KeyEntry>()).map(\.recipe?.name) == ["homelab"])
    }

    @Test("forgetting removes the record and its entries")
    func forgetting() throws {
        try context.recordIfNew(DiceKey.example)
        try context.addEntry(for: try key(.ssh, "github"), diceKeyID: DiceKey.example.id)
        try context.forget(try #require(try context.record(for: DiceKey.example.id)))
        #expect(try context.fetchCount(FetchDescriptor<DiceKeyRecord>()) == 0)
        #expect(try context.fetchCount(FetchDescriptor<KeyEntry>()) == 0)
    }
}
