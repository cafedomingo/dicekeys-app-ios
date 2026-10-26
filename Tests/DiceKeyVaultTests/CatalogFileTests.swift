//
//  CatalogFileTests.swift
//  DiceKeyVaultTests
//

import Derivation
import Foundation
import KeyFormats
import SwiftData
import Testing

@testable import DiceKeyVault

@MainActor
struct CatalogFileTests {
    private let context: ModelContext

    init() throws {
        context = ModelContext(try Catalog.container(syncing: false, inMemory: true))
    }

    private func catalogWithKeys() throws -> CatalogFile {
        try context.recordIfNew(DiceKey.example)
        for recipe in [
            try KeyRecipe(kind: .ssh, name: "github"),
            try KeyRecipe(kind: .passphrase, name: "nas", style: .memorable(words: 7, digitsAndUppercase: true))
        ] {
            try context.addEntry(
                for: DerivedKey.derive(seed: DiceKey.example.seed, recipe: recipe), diceKeyID: DiceKey.example.id)
        }
        return CatalogFile(
            records: try context.fetch(FetchDescriptor<DiceKeyRecord>()),
            entries: try context.fetch(FetchDescriptor<KeyEntry>()))
    }

    @Test("the file reads back as it was written")
    func roundTrip() throws {
        let file = try catalogWithKeys()
        #expect(file.keys.count == 2)
        #expect(try CatalogFile(json: file.json()) == file)
        #expect(String(decoding: try file.json(), as: UTF8.self).contains("\n"))
    }

    @Test("the QR code's link carries the list")
    func importLink() throws {
        let file = try catalogWithKeys()
        let restored = try CatalogFile(importURL: try file.importURL)
        #expect(restored.diceKeys == file.diceKeys)
        #expect(restored.keys.map(\.recipe) == file.keys.map(\.recipe))
    }

    @Test("merging adds only what is missing")
    func merge() throws {
        let file = try catalogWithKeys()
        #expect(try file.merge(into: context) == (diceKeys: 0, keys: 0, unreadable: 0))
        let empty = ModelContext(try Catalog.container(syncing: false, inMemory: true))
        #expect(try file.merge(into: empty) == (diceKeys: 1, keys: 2, unreadable: 0))
        #expect(try empty.entries(for: DiceKey.example.id).compactMap(\.recipe?.name) == ["github", "nas"])
    }

    @Test("the file and the QR code's link leave out the default keys")
    func exportLeavesOutDefaults() throws {
        try context.recordIfNew(DiceKey.example)
        let github = try KeyRecipe(kind: .ssh, name: "github")
        try context.addEntry(
            for: DerivedKey.derive(seed: DiceKey.example.seed, recipe: github), diceKeyID: DiceKey.example.id)
        let file = CatalogFile(
            records: try context.fetch(FetchDescriptor<DiceKeyRecord>()),
            entries: try context.fetch(FetchDescriptor<KeyEntry>()))
        #expect(file.keys.map(\.recipe.name) == ["github"])
        #expect(try CatalogFile(importURL: try file.importURL).keys.map(\.recipe.name) == ["github"])
    }

    @Test("importing a DiceKey records it with the default keys")
    func importAddsDefaults() throws {
        let file = try catalogWithKeys()
        let empty = ModelContext(try Catalog.container(syncing: false, inMemory: true))
        try file.merge(into: empty)
        #expect(
            try empty.entries(for: DiceKey.example.id).compactMap(\.recipe).filter(\.isDefault) == KeyRecipe.defaults)
    }

    @Test("a default in a hand-made file doesn't stand in for the other")
    func defaultInAFileIsNotBoth() throws {
        let id = DiceKey.example.id
        let json = """
            {"v":1,"diceKeys":[{"id":"\(id)","name":"Home","centerFace":"M1t"}],"keys":[
            {"diceKey":"\(id)","kind":"ssh"}]}
            """
        let empty = ModelContext(try Catalog.container(syncing: false, inMemory: true))
        #expect(try CatalogFile(json: Data(json.utf8)).merge(into: empty) == (diceKeys: 1, keys: 0, unreadable: 0))
        #expect(try empty.entries(for: id).compactMap(\.recipe) == KeyRecipe.defaults)
    }

    @Test("two DiceKeys with a key of the same recipe each keep theirs in the file")
    func sameRecipeOnTwoDiceKeys() throws {
        let other = try DiceKey(text: "B2rA1t" + DiceKey.example.text.dropFirst(6))
        let github = try KeyRecipe(kind: .ssh, name: "github")
        for diceKey in [DiceKey.example, other] {
            try context.recordIfNew(diceKey)
            try context.addEntry(for: DerivedKey.derive(seed: diceKey.seed, recipe: github), diceKeyID: diceKey.id)
        }
        let file = CatalogFile(
            records: try context.fetch(FetchDescriptor<DiceKeyRecord>()),
            entries: try context.fetch(FetchDescriptor<KeyEntry>()))
        #expect(Set(file.keys.map(\.diceKey)) == [DiceKey.example.id, other.id])
        let empty = ModelContext(try Catalog.container(syncing: false, inMemory: true))
        #expect(try file.merge(into: empty) == (diceKeys: 2, keys: 2, unreadable: 0))
    }

    @Test("a DiceKey a sync recorded twice is in the file once, by the name it shows")
    func syncedRecordsExportOnce() throws {
        for name in [DiceKey.example.defaultName, "Home box"] {
            let record = DiceKeyRecord(diceKey: DiceKey.example)
            record.name = name
            context.insert(record)
        }
        let file = CatalogFile(records: try context.fetch(FetchDescriptor<DiceKeyRecord>()), entries: [])
        #expect(file.diceKeys.map(\.name) == ["Home box"])
    }

    @Test("an imported public key is ignored, and filled in from the dice on unlock")
    func publicKeysComeFromTheDice() throws {
        var file = try catalogWithKeys()
        let genuine = file.keys[0].publicKey
        file.keys[0].publicKey = "ssh-ed25519 AAAAattacker github"
        let empty = ModelContext(try Catalog.container(syncing: false, inMemory: true))
        try file.merge(into: empty)
        #expect(try empty.entries(for: DiceKey.example.id).allSatisfy { $0.publicKey == nil })
        try empty.fillPublicKeys(for: DiceKey.example)
        #expect(try empty.entries(for: DiceKey.example.id).first { $0.recipe?.name == "github" }?.publicKey == genuine)
    }

    @Test("a passphrase without its style, a field no recipe has, or a key without its DiceKey, is skipped")
    func skipsWhatCantBeRebuilt() throws {
        let id = DiceKey.example.id
        let json = """
            {"v":1,"diceKeys":[{"id":"\(id)","name":"Home","centerFace":"M1t"}],"keys":[
            {"diceKey":"\(id)","kind":"passphrase","name":"x"},
            {"diceKey":"\(id)","kind":"ssh","name":"y","flavor":"spicy"},
            {"diceKey":"unknown","kind":"ssh","name":"z"}]}
            """
        let file = try CatalogFile(json: Data(json.utf8))
        let empty = ModelContext(try Catalog.container(syncing: false, inMemory: true))
        #expect(try file.merge(into: empty) == (diceKeys: 1, keys: 0, unreadable: 3))
    }

    @Test("a key a later version wrote is skipped and counted, and the rest of the file still reads")
    func unknownKeysAreSkipped() throws {
        let id = DiceKey.example.id
        let json = """
            {"v":1,"diceKeys":[{"id":"\(id)","name":"Home","centerFace":"M1t"}],"keys":[
            {"diceKey":"\(id)","kind":"ssh","name":"github"},
            {"diceKey":"\(id)","kind":"pgp","name":"mail"},
            {"diceKey":"\(id)","kind":"passphrase","name":"nas","style":{"diceware":{"words":6}}}]}
            """
        let file = try CatalogFile(json: Data(json.utf8))
        #expect(file.keys.map(\.recipe.name) == ["github"])
        let empty = ModelContext(try Catalog.container(syncing: false, inMemory: true))
        #expect(try file.merge(into: empty) == (diceKeys: 1, keys: 1, unreadable: 2))
    }

    @Test("a newer format, or something else entirely, is refused")
    func refusals() {
        #expect(throws: CatalogFile.Failure.newerVersion(2)) {
            try CatalogFile(json: Data(#"{"v":2,"diceKeys":[],"keys":[]}"#.utf8))
        }
        #expect(throws: CatalogFile.Failure.notACatalog) { try CatalogFile(json: Data("{}".utf8)) }
        #expect(throws: CatalogFile.Failure.notACatalog) {
            try CatalogFile(importURL: URL(string: "dicekeyvault://import?catalog=%21")!)
        }
    }

    @Test("names with emoji, quotes and other scripts survive the file, the QR code's link and a merge")
    func specialNames() throws {
        try context.recordIfNew(DiceKey.example)
        let names = ["🧨", "👩‍💻 laptop", #"quote " and \ backslash"#, "مفتاح الخادم", "日本語の鍵", "line\u{2028}separator"]
        for name in names {
            let recipe = try KeyRecipe(kind: .ssh, name: name)
            try context.addEntry(
                for: DerivedKey.derive(seed: DiceKey.example.seed, recipe: recipe), diceKeyID: DiceKey.example.id)
        }
        let file = CatalogFile(
            records: try context.fetch(FetchDescriptor<DiceKeyRecord>()),
            entries: try context.fetch(FetchDescriptor<KeyEntry>()))
        #expect(try CatalogFile(json: file.json()) == file)
        #expect(try CatalogFile(importURL: try file.importURL).keys.map(\.recipe) == file.keys.map(\.recipe))
        let empty = ModelContext(try Catalog.container(syncing: false, inMemory: true))
        try file.merge(into: empty)
        #expect(Set(try empty.entries(for: DiceKey.example.id).compactMap(\.recipe?.name)) == Set(names))
    }
}
