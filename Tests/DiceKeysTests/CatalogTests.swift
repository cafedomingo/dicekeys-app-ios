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
        DerivedKey.derive(seed: DiceKey.example.toSeed(), recipe: try KeyRecipe(kind: kind, name: name, style: style))
    }

    @Test("a DiceKey is new on first scan and known after, named by its center die")
    func recognition() throws {
        #expect(try context.recognize(DiceKey.example) == false)
        #expect(try context.recognize(DiceKey.example) == true)
        let record = try #require(try context.record(for: DiceKey.example.id))
        #expect(record.name == "DiceKey with M1 in center")
        #expect(record.centerFace == DiceKey.example.centerFace.humanReadableForm)
    }

    @Test("a passphrase whose style can't be read rebuilds nothing, not the default style")
    func unreadableStyle() throws {
        let entry = KeyEntry(
            diceKeyID: DiceKey.example.id, recipe: try KeyRecipe(kind: .passphrase, name: "nas"), publicKey: nil)
        entry.style = Data(#"{"futureStyle":{}}"#.utf8)
        #expect(entry.recipe == nil)
        entry.style = nil
        #expect(entry.recipe == nil)
    }

    @Test("an entry rebuilds the same recipe, style included")
    func entryRoundTrip() throws {
        let style = PassphraseStyle.memorable(words: 7, digitAndCapital: true)
        let passphrase = try key(.passphrase, "nas", style: style)
        try context.save(passphrase, for: DiceKey.example.id)
        try context.save(try key(.ssh, "github"), for: DiceKey.example.id)
        let entries = try context.entries(for: DiceKey.example.id)
        #expect(entries.map(\.name) == ["github", "nas"])
        #expect(entries[1].recipe == passphrase.recipe)
        #expect(entries[1].publicKey == nil)
        #expect(entries[0].publicKey?.hasPrefix("ssh-ed25519 ") == true)
    }

    @Test("the same key saved twice, or synced from two devices, appears once")
    func duplicates() throws {
        let ssh = try key(.ssh, "github")
        try context.save(ssh, for: DiceKey.example.id)
        try context.save(ssh, for: DiceKey.example.id)
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
}
