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
        context = ModelContext(try Catalog.container(inMemory: true))
    }

    private func key(_ kind: KeyKind, _ name: String, style: PassphraseStyle = .standard) throws -> DerivedKey {
        DerivedKey.derive(seed: DiceKey.example.seed, recipe: try KeyRecipe(kind: kind, name: name, style: style))
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

    @Test("an entry rebuilds the same recipe, style included")
    func entryRoundTrip() throws {
        let style = PassphraseStyle.memorable(words: 7, digitAndCapital: true)
        let passphrase = try key(.passphrase, "nas", style: style)
        try context.addEntry(for: passphrase, diceKeyID: DiceKey.example.id)
        try context.addEntry(for: try key(.ssh, "github"), diceKeyID: DiceKey.example.id)
        let entries = try context.entries(for: DiceKey.example.id)
        #expect(entries.map(\.name) == ["github", "nas"])
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

    @Test("an entry of an unknown kind is skipped")
    func unknownKind() throws {
        let entry = KeyEntry(diceKeyID: "x", recipe: try key(.age, "backup").recipe, publicKey: nil)
        entry.kind = "future"
        context.insert(entry)
        #expect(try context.entries(for: "x").isEmpty)
    }

    @Test("a passphrase whose style can't be read is left out, not guessed")
    func unreadableStyle() throws {
        let entry = KeyEntry(diceKeyID: "x", recipe: try key(.passphrase, "nas").recipe, publicKey: nil)
        entry.style = Data("{\"future\":{}}".utf8)
        #expect(entry.recipe == nil)
    }

    @Test("deleting a key removes its synced copies and leaves the other keys")
    func deletingAKey() throws {
        let github = try key(.ssh, "github")
        try context.addEntry(for: github, diceKeyID: DiceKey.example.id)
        context.insert(KeyEntry(diceKeyID: DiceKey.example.id, recipe: github.recipe, publicKey: github.publicKey))
        try context.addEntry(for: try key(.ssh, "homelab"), diceKeyID: DiceKey.example.id)
        try context.deleteKey(github.recipe, diceKeyID: DiceKey.example.id)
        #expect(try context.fetch(FetchDescriptor<KeyEntry>()).map(\.name) == ["homelab"])
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
