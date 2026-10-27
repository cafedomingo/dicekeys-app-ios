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
    /// The nameless WireGuard recipe that TestFlight builds recorded as a default.
    private static let testBuildWireGuardDefault = #"{"kind":"wireguard"}"#

    private let context: ModelContext

    init() throws {
        context = ModelContext(try Catalog.container(syncing: false, inMemory: true))
    }

    private func key(_ kind: KeyKind, _ name: String, style: PassphraseStyle = .standard) throws -> DerivedKey {
        DerivedKey.derive(seed: DiceKey.example.seed, recipe: try KeyRecipe(kind: kind, name: name, style: style))
    }

    /// A row holding this text as its recipe, as a sync or an earlier build can leave one.
    @discardableResult
    private func insertRow(_ recipeJSON: String) -> KeyEntry {
        let entry = KeyEntry(diceKeyID: DiceKey.example.id, recipe: KeyRecipe.defaults[0], publicKey: nil)
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
        #expect(entries.allSatisfy { $0.publicKey == nil })
    }

    @Test("recording saves the record even when its default keys arrived from a sync before it")
    func recordingSavesWhenDefaultsAreThere() throws {
        context.insert(KeyEntry(diceKeyID: DiceKey.example.id, recipe: KeyRecipe.defaults[0], publicKey: nil))
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
            try context.entries(for: DiceKey.example.id).map(\.publicKey)
                == KeyRecipe.defaults.map { DerivedKey.derive(seed: DiceKey.example.seed, recipe: $0).publicKey })
        #expect(
            try context.entries(for: DiceKey.example.id).map(\.postQuantumPublicKey)
                == KeyRecipe.defaults.map {
                    DerivedKey.derive(seed: DiceKey.example.seed, recipe: $0).postQuantum?.recipient
                })
    }

    @Test("an age key records its post-quantum recipient when made, and one recorded without it fills it in")
    func ageRecordsPostQuantumRecipient() throws {
        let made = try key(.age, "backups")
        let entry = try context.addEntry(for: made, diceKeyID: DiceKey.example.id)
        #expect(entry.postQuantumPublicKey == made.postQuantum?.recipient)
        #expect(!entry.needsPublicKey)
        let recipe = try #require(KeyRecipe.defaults.first { $0.kind == .age })
        let derived = DerivedKey.derive(seed: DiceKey.example.seed, recipe: recipe)
        let earlier = KeyEntry(diceKeyID: DiceKey.example.id, recipe: recipe, publicKey: derived.publicKey)
        context.insert(earlier)
        try context.save()
        #expect(earlier.needsPublicKey)
        let watched = try context.fetch(FetchDescriptor(predicate: KeyEntry.mayNeedPublicKey))
        #expect(watched.map(\.persistentModelID).contains(earlier.persistentModelID))
        let ssh = try context.addEntry(for: try key(.ssh, "github"), diceKeyID: DiceKey.example.id)
        #expect(!ssh.needsPublicKey)
        try context.fillPublicKeys(for: DiceKey.example)
        #expect(earlier.publicKey == derived.publicKey)
        #expect(earlier.postQuantumPublicKey == derived.postQuantum?.recipient)
        #expect(!earlier.needsPublicKey)
    }

    @Test("filling in public keys fills every copy a sync made, and a passphrase never needs one")
    func fillCoversCopiesAndSkipsSecrets() throws {
        try context.recordIfNew(DiceKey.example)
        let copy = KeyEntry(diceKeyID: DiceKey.example.id, recipe: KeyRecipe.defaults[0], publicKey: nil)
        copy.created = .distantFuture
        context.insert(copy)
        let passphrase = KeyEntry(
            diceKeyID: DiceKey.example.id, recipe: try KeyRecipe(kind: .passphrase, name: "bank"), publicKey: nil)
        context.insert(passphrase)
        #expect(!passphrase.needsPublicKey)
        try context.fillPublicKeys(for: DiceKey.example)
        #expect(
            copy.publicKey == DerivedKey.derive(seed: DiceKey.example.seed, recipe: KeyRecipe.defaults[0]).publicKey)
        #expect(try context.fetch(FetchDescriptor<KeyEntry>()).filter(\.needsPublicKey).isEmpty)
    }

    @Test("default keys come first, in their own order even when made in another, then the named keys")
    func defaultsSortFirst() throws {
        for (index, recipe) in KeyRecipe.defaults.enumerated() {
            let entry = KeyEntry(diceKeyID: DiceKey.example.id, recipe: recipe, publicKey: nil)
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
        context.insert(KeyEntry(diceKeyID: DiceKey.example.id, recipe: KeyRecipe.defaults[0], publicKey: nil))
        #expect(try context.entries(for: DiceKey.example.id).count == KeyRecipe.defaults.count)
    }

    @Test("a WireGuard default a test build recorded is kept but left out of lists, counts, export and paper")
    func testBuildWireGuardDefaultIsLeftOut() throws {
        try context.recordIfNew(DiceKey.example)
        let github = try key(.ssh, "github")
        try context.addEntry(for: github, diceKeyID: DiceKey.example.id)
        let leftover = insertRow(Self.testBuildWireGuardDefault)
        try context.addMissingDefaults()
        try context.fillPublicKeys(for: DiceKey.example)
        let shown = KeyRecipe.defaults + [github.recipe]
        #expect(try context.entries(for: DiceKey.example.id).map(\.recipeJSON) == shown.map(\.json))
        #expect(leftover.publicKey == nil)
        let rows = try context.fetch(FetchDescriptor<KeyEntry>())
        #expect(rows.count == shown.count + 1)
        let record = try #require(try context.record(for: DiceKey.example.id))
        #expect(CatalogFile(records: [record], entries: rows).keys.map(\.recipe) == [github.recipe])
        #expect(
            RecoveryCode(diceKey: .example, record: record, entries: rows).catalog.keys.map(\.recipe)
                == [github.recipe])
    }

    @Test(
        "the backfill adds each default a DiceKey lacks, and a test build's WireGuard default isn't one",
        arguments: [[], [KeyRecipe.defaults[0].json]])
    func backfillAddsEachMissingDefault(_ synced: [String]) throws {
        context.insert(DiceKeyRecord(diceKey: DiceKey.example))
        for text in [Self.testBuildWireGuardDefault] + synced { insertRow(text) }
        try context.addMissingDefaults()
        #expect(try context.entries(for: DiceKey.example.id).map(\.recipeJSON) == KeyRecipe.defaults.map(\.json))
        #expect(try context.fetchCount(FetchDescriptor<KeyEntry>()) == KeyRecipe.defaults.count + 1)
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
            #"{"kind":"passphrase"}"#,
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
