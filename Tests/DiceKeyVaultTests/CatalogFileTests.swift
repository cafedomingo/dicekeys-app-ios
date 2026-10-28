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
        return try CatalogFile(
            records: try context.fetch(FetchDescriptor<DiceKeyRecord>()),
            entries: try context.fetch(FetchDescriptor<KeyEntry>()))
    }

    @Test("the file reads back as it was written")
    func roundTrip() throws {
        let file = try catalogWithKeys()
        #expect(file.keys.count == 4)
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

    @Test("the named keys are the keys without the defaults")
    func namedKeysLeaveOutDefaults() throws {
        let file = try catalogWithKeys()
        #expect(file.keys.count == KeyRecipe.defaults.count + 2)
        #expect(file.namedKeys.map(\.recipe.name) == ["github", "nas"])
        #expect(file.namedKeys.allSatisfy { !$0.recipe.isDefault })
    }

    @Test("the file and the QR code's link carry the default keys, then the named ones")
    func exportCarriesDefaults() throws {
        try context.recordIfNew(DiceKey.example)
        let github = try KeyRecipe(kind: .ssh, name: "github")
        try context.addEntry(
            for: DerivedKey.derive(seed: DiceKey.example.seed, recipe: github), diceKeyID: DiceKey.example.id)
        let file = try CatalogFile(
            records: try context.fetch(FetchDescriptor<DiceKeyRecord>()),
            entries: try context.fetch(FetchDescriptor<KeyEntry>()))
        #expect(file.keys.map(\.recipe) == KeyRecipe.defaults + [github])
        #expect(try CatalogFile(importURL: try file.importURL).keys.map(\.recipe) == KeyRecipe.defaults + [github])
    }

    @Test("the file writes every algorithm's public key by its type, for keys with a public half")
    func exportWritesPublicKeys() throws {
        try context.recordIfNew(DiceKey.example)
        let recipes = [
            try KeyRecipe(kind: .age, name: "backups"),
            try KeyRecipe(kind: .ssh, name: "github"),
            try KeyRecipe(kind: .passphrase, name: "nas", style: .memorable(words: 7, digitsAndUppercase: true))
        ]
        for recipe in recipes {
            try context.addEntry(
                for: DerivedKey.derive(seed: DiceKey.example.seed, recipe: recipe), diceKeyID: DiceKey.example.id)
        }
        try context.fillPublicKeys(for: DiceKey.example)
        let file = try CatalogFile(
            records: try context.fetch(FetchDescriptor<DiceKeyRecord>()),
            entries: try context.fetch(FetchDescriptor<KeyEntry>()))
        #expect(file.keys.map(\.recipe) == KeyRecipe.defaults + recipes)
        for key in file.keys {
            let derived = DerivedKey.derive(seed: DiceKey.example.seed, recipe: key.recipe).publicKeys
            #expect(key.publicKeys == (key.recipe.kind.hasPublicKey ? derived : nil))
        }
        let root = try #require(try JSONSerialization.jsonObject(with: file.json()) as? [String: Any])
        let objects = try #require(root["keys"] as? [[String: Any]])
        let age = try #require(objects.first { $0["kind"] as? String == "age" && $0["name"] == nil })
        #expect(Set(try #require(age["publicKeys"] as? [String: String]).keys) == ["mlkem768x25519", "x25519"])
        let passphrase = try #require(objects.first { $0["kind"] as? String == "passphrase" })
        #expect(passphrase["publicKeys"] == nil)
        #expect(try CatalogFile(json: file.json()) == file)
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
        let file = try CatalogFile(
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
        let file = try CatalogFile(records: try context.fetch(FetchDescriptor<DiceKeyRecord>()), entries: [])
        #expect(file.diceKeys.map(\.name) == ["Home box"])
    }

    @Test("an imported public key is ignored, and filled in from the dice on unlock")
    func publicKeysComeFromTheDice() throws {
        var file = try catalogWithKeys()
        let index = try #require(file.keys.firstIndex { $0.recipe.name == "github" })
        let genuine = try #require(file.keys[index].publicKeys?["ed25519"])
        file.keys[index].publicKeys = ["ed25519": "ssh-ed25519 AAAAattacker github"]
        let empty = ModelContext(try Catalog.container(syncing: false, inMemory: true))
        try file.merge(into: empty)
        #expect(try empty.entries(for: DiceKey.example.id).allSatisfy { $0.publicKeys.isEmpty })
        try empty.fillPublicKeys(for: DiceKey.example)
        let github = try empty.entries(for: DiceKey.example.id).first { $0.recipe?.name == "github" }
        #expect(github?.publicKeys["ed25519"] == genuine)
    }

    @Test("a key whose public keys aren't a map of text is skipped and counted, and the rest still reads")
    func malformedPublicKeysSkipsTheKey() throws {
        let id = DiceKey.example.id
        let json = """
            {"v":1,"diceKeys":[{"id":"\(id)","name":"Home","centerFace":"M1t"}],"keys":[
            {"diceKey":"\(id)","kind":"ssh","name":"w","publicKeys":"nope"},
            {"diceKey":"\(id)","kind":"ssh","name":"github"}]}
            """
        let file = try CatalogFile(json: Data(json.utf8))
        #expect(file.keys.map(\.recipe.name) == ["github"])
        let empty = ModelContext(try Catalog.container(syncing: false, inMemory: true))
        #expect(try file.merge(into: empty) == (diceKeys: 1, keys: 1, unreadable: 1))
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
        let file = try CatalogFile(
            records: try context.fetch(FetchDescriptor<DiceKeyRecord>()),
            entries: try context.fetch(FetchDescriptor<KeyEntry>()))
        #expect(try CatalogFile(json: file.json()) == file)
        #expect(try CatalogFile(importURL: try file.importURL).keys.map(\.recipe) == file.keys.map(\.recipe))
        let empty = ModelContext(try Catalog.container(syncing: false, inMemory: true))
        try file.merge(into: empty)
        #expect(Set(try empty.entries(for: DiceKey.example.id).compactMap(\.recipe?.name)) == Set(names))
    }
}
