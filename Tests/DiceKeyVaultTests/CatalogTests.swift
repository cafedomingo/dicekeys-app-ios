//
//  CatalogTests.swift
//  DiceKeyVaultTests
//

import Derivation
import Foundation
import KeyFormats
import SwiftData
import Testing

@testable import DiceKeyVault

@MainActor
struct CatalogTests {
    private let container: ModelContainer
    private let context: ModelContext

    init() throws {
        container = try Catalog.container(syncing: false, inMemory: true)
        context = ModelContext(container)
    }

    private func key(_ kind: KeyKind, _ name: String, style: PassphraseStyle = .standard) throws -> DerivedKey {
        DerivedKey.derive(seed: DiceKey.example.seed, recipe: try KeyRecipe(kind: kind, name: name, style: style))
    }

    private func ageDefault() throws -> KeyRecipe {
        try #require(KeyRecipe.defaults.first { $0.kind == .age })
    }

    /// A row holding this text as its recipe, as a sync can leave one.
    @discardableResult
    private func insertRow(_ recipeJSON: String) -> KeyEntry {
        let entry = KeyEntry(diceKeyID: DiceKey.example.id, recipe: KeyRecipe.defaults[0])
        entry.recipeJSON = recipeJSON
        context.insert(entry)
        return entry
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

    @Test("with both renamed and recorded at the same moment, the choice doesn't depend on the order they're read in")
    func sameMomentRenamesPickOne() throws {
        let created = Date.now
        let office = syncedDuplicate(named: "Office", created: created)
        let home = syncedDuplicate(named: "Home box", created: created)
        #expect([office, home].uniqueDiceKeys.map(\.name) == ["Home box"])
        #expect([home, office].uniqueDiceKeys.map(\.name) == ["Home box"])
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
        #expect(record.centerFace == DiceKey.example.centerFace.text)
    }

    @Test("recording a DiceKey adds the default keys, without public keys, and says so only the first time")
    func recordingAddsDefaults() throws {
        #expect(try context.recordIfNew(DiceKey.example) == true)
        #expect(try context.recordIfNew(DiceKey.example) == false)
        let entries = try context.entries(for: DiceKey.example.id)
        #expect(entries.compactMap(\.recipe) == KeyRecipe.defaults)
        #expect(entries.allSatisfy { $0.publicKeys.isEmpty })
    }

    @Test("recording saves the record even when its default keys arrived from a sync before it")
    func recordingSavesWhenDefaultsAreThere() throws {
        context.insert(KeyEntry(diceKeyID: DiceKey.example.id, recipe: KeyRecipe.defaults[0]))
        try context.save()
        #expect(try context.recordIfNew(DiceKey.example) == true)
        #expect(!context.hasChanges)
    }

    @Test("a DiceKey from before the defaults gets them once and saved, without its seed, whatever copies a sync made")
    func missingDefaultsAreAddedOnce() throws {
        _ = syncedDuplicate(created: .distantPast)
        _ = syncedDuplicate(created: .now)
        try context.addMissingDefaults()
        try context.addMissingDefaults()
        #expect(try context.fetchCount(FetchDescriptor<KeyEntry>()) == KeyRecipe.defaults.count)
        #expect(!context.hasChanges)
    }

    @Test("filling in public keys gives each default key the one its DiceKey derives")
    func defaultsFillFromTheDiceKey() throws {
        try context.recordIfNew(DiceKey.example)
        try context.fillPublicKeys(for: DiceKey.example)
        #expect(
            try context.entries(for: DiceKey.example.id).map(\.publicKeys)
                == KeyRecipe.defaults.map { DerivedKey.derive(seed: DiceKey.example.seed, recipe: $0).publicKeys })
    }

    @Test(
        "a key needs a public key until it holds one for every algorithm of its kind, and a secret never does",
        arguments: [
            (KeyKind.ssh, [String: String](), true),
            (.ssh, ["ed25519": "x"], false),
            (.age, ["x25519": "x"], true),
            (.age, ["x25519": "x", "mlkem768x25519": "y"], false),
            (.age, ["x25519": "x", "mlkem768x25519": "y", "future": "z"], false),
            (.passphrase, [:], false),
            (.wallet, [:], false)
        ])
    func needsPublicKey(kind: KeyKind, publicKeys: [String: String], expected: Bool) throws {
        let entry = KeyEntry(
            diceKeyID: DiceKey.example.id, recipe: try KeyRecipe(kind: kind, name: "test"), publicKeys: publicKeys)
        #expect(entry.needsPublicKey == expected)
    }

    @Test("an age key is recorded with both its recipients")
    func ageRecordsBothRecipients() throws {
        let backups = try key(.age, "backups")
        let entry = try context.addEntry(for: backups, diceKeyID: DiceKey.example.id)
        #expect(entry.publicKeys == backups.publicKeys)
        #expect(Set(entry.publicKeys.keys) == ["x25519", "mlkem768x25519"])
        #expect(!entry.needsPublicKey)
    }

    @Test("filling in public keys keeps an algorithm this version doesn't know")
    func fillKeepsUnknownAlgorithms() throws {
        let recipe = try ageDefault()
        let derived = DerivedKey.derive(seed: DiceKey.example.seed, recipe: recipe)
        let row = KeyEntry(
            diceKeyID: DiceKey.example.id, recipe: recipe,
            publicKeys: ["x25519": try #require(derived.publicKeys["x25519"]), "future-algorithm": "future-key"])
        context.insert(row)
        try context.save()
        try context.fillPublicKeys(for: .example)
        let fresh = ModelContext(container)
        let stored = try #require(try fresh.fetch(FetchDescriptor<KeyEntry>()).first)
        let expected = derived.publicKeys.merging(["future-algorithm": "future-key"]) { first, _ in first }
        #expect(stored.publicKeys == expected)
    }

    @Test("the fill runs for unlocked DiceKeys' rows that miss a public key, and for no other")
    func fillTriggerPicksUnlockedRowsMissingAKey() throws {
        let age = try ageDefault()
        let derived = DerivedKey.derive(seed: DiceKey.example.seed, recipe: age)
        let x25519 = try #require(derived.publicKeys["x25519"])
        let ageRow = KeyEntry(diceKeyID: DiceKey.example.id, recipe: age, publicKeys: ["x25519": x25519])
        let github = try key(.ssh, "github")
        let complete = KeyEntry(diceKeyID: DiceKey.example.id, recipe: github.recipe, publicKeys: github.publicKeys)
        let passphrase = KeyEntry(diceKeyID: DiceKey.example.id, recipe: try key(.passphrase, "bank").recipe)
        let locked = KeyEntry(diceKeyID: "locked", recipe: KeyRecipe.defaults[0])
        for row in [ageRow, complete, passphrase, locked] { context.insert(row) }
        try context.save()
        let rows = try context.fetch(FetchDescriptor<KeyEntry>())
        #expect(rows.keysToFill { $0 == DiceKey.example.id } == [ageRow.persistentModelID])
    }

    @Test("filling in public keys fills every copy a sync made, and a passphrase never needs one")
    func fillCoversCopiesAndSkipsSecrets() throws {
        try context.recordIfNew(DiceKey.example)
        let copy = KeyEntry(diceKeyID: DiceKey.example.id, recipe: KeyRecipe.defaults[0])
        copy.created = .distantFuture
        context.insert(copy)
        let passphrase = KeyEntry(
            diceKeyID: DiceKey.example.id, recipe: try KeyRecipe(kind: .passphrase, name: "bank"))
        context.insert(passphrase)
        #expect(!passphrase.needsPublicKey)
        try context.fillPublicKeys(for: DiceKey.example)
        #expect(
            copy.publicKeys == DerivedKey.derive(seed: DiceKey.example.seed, recipe: KeyRecipe.defaults[0]).publicKeys)
        #expect(try context.fetch(FetchDescriptor<KeyEntry>()).filter(\.needsPublicKey).isEmpty)
    }

    @Test("default keys come first, in their own order even when made in another, then the named keys")
    func defaultsSortFirst() throws {
        for (index, recipe) in KeyRecipe.defaults.enumerated() {
            let entry = KeyEntry(diceKeyID: DiceKey.example.id, recipe: recipe)
            entry.created = .distantPast.addingTimeInterval(-Double(index))
            context.insert(entry)
        }
        let aaa = try key(.ssh, "aaa")
        try context.addEntry(for: aaa, diceKeyID: DiceKey.example.id)
        #expect(
            try context.entries(for: DiceKey.example.id).compactMap(\.recipe) == KeyRecipe.defaults + [aaa.recipe])
    }

    @Test("default keys that two devices each added show once")
    func syncedDefaultsCollapse() throws {
        try context.recordIfNew(DiceKey.example)
        context.insert(KeyEntry(diceKeyID: DiceKey.example.id, recipe: KeyRecipe.defaults[0]))
        #expect(try context.entries(for: DiceKey.example.id).count == KeyRecipe.defaults.count)
    }

    @Test(
        "a key a newer version made, a kind or field this one doesn't know, is kept but left out of lists, and stops the file and paper",
        arguments: [#"{"kind":"totp","name":"github"}"#, #"{"kind":"ssh","name":"github","size":4096}"#])
    func newerKeyIsKeptAndStopsFileAndPaper(_ recipeJSON: String) throws {
        try context.recordIfNew(DiceKey.example)
        let newer = insertRow(recipeJSON)
        try context.fillPublicKeys(for: DiceKey.example)
        #expect(try context.entries(for: DiceKey.example.id).map(\.recipeJSON) == KeyRecipe.defaults.map(\.json))
        #expect(newer.publicKeys.isEmpty)
        let rows = try context.fetch(FetchDescriptor<KeyEntry>())
        #expect(rows.count == KeyRecipe.defaults.count + 1)
        let record = try #require(try context.record(for: DiceKey.example.id))
        #expect(throws: CatalogFile.Failure.newerKeys) { try CatalogFile(records: [record], entries: rows) }
        #expect(throws: CatalogFile.Failure.newerKeys) {
            try RecoveryCode(diceKey: .example, record: record, entries: rows)
        }
    }

    @Test(
        "the backfill adds each default a DiceKey lacks",
        arguments: [[], [KeyRecipe.defaults[0].json]])
    func backfillAddsEachMissingDefault(_ synced: [String]) throws {
        context.insert(DiceKeyRecord(diceKey: DiceKey.example))
        for text in synced { insertRow(text) }
        try context.addMissingDefaults()
        #expect(try context.entries(for: DiceKey.example.id).map(\.recipeJSON) == KeyRecipe.defaults.map(\.json))
        #expect(try context.fetchCount(FetchDescriptor<KeyEntry>()) == KeyRecipe.defaults.count)
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
        #expect(entries[1].publicKeys.isEmpty)
        #expect(entries[0].publicKeys["ed25519"]?.hasPrefix("ssh-ed25519 ") == true)
    }

    @Test("the same key saved twice, or synced from two devices, appears once")
    func duplicates() throws {
        let ssh = try key(.ssh, "github")
        try context.addEntry(for: ssh, diceKeyID: DiceKey.example.id)
        try context.addEntry(for: ssh, diceKeyID: DiceKey.example.id)
        context.insert(KeyEntry(diceKeyID: DiceKey.example.id, recipe: ssh.recipe, publicKeys: ssh.publicKeys))
        #expect(try context.entries(for: DiceKey.example.id).count == 1)
    }

    @Test("a key already made is found by its recipe, so New key can say so instead of saving it again")
    func existingKeyIsFound() throws {
        let github = try key(.ssh, "github")
        #expect(try context.entry(for: github.recipe, diceKeyID: DiceKey.example.id) == nil)
        let saved = try context.addEntry(for: github, diceKeyID: DiceKey.example.id)
        #expect(try context.entry(for: github.recipe, diceKeyID: DiceKey.example.id) === saved)
        #expect(try context.entry(for: try key(.age, "github").recipe, diceKeyID: DiceKey.example.id) == nil)
    }

    @Test("of two synced copies, the older stands for the key")
    func olderCopyWins() throws {
        let ssh = try key(.ssh, "github")
        let newer = KeyEntry(diceKeyID: DiceKey.example.id, recipe: ssh.recipe)
        newer.created = .now
        context.insert(newer)
        let older = KeyEntry(diceKeyID: DiceKey.example.id, recipe: ssh.recipe, publicKeys: ssh.publicKeys)
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
            #"{"kind":"passphrase"}"#,
            ""
        ])
    func unreadableRecipe(_ text: String) throws {
        let entry = KeyEntry(diceKeyID: "x", recipe: try key(.age, "backup").recipe)
        entry.recipeJSON = text
        context.insert(entry)
        #expect(entry.recipe == nil)
        #expect(try context.entries(for: "x").isEmpty)
    }

    @Test("deleting a key removes its synced copies and leaves the other keys")
    func deletingAKey() throws {
        let github = try key(.ssh, "github")
        try context.addEntry(for: github, diceKeyID: DiceKey.example.id)
        context.insert(KeyEntry(diceKeyID: DiceKey.example.id, recipe: github.recipe, publicKeys: github.publicKeys))
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
