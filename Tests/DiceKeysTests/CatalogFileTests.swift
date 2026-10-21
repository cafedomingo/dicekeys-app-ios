//
//  CatalogFileTests.swift
//  DiceKeysTests
//

import Derivation
import Foundation
import KeyFormats
import SwiftData
import Testing

@testable import DiceKeys

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
            try KeyRecipe(kind: .passphrase, name: "nas", style: .memorable(words: 7, digitAndCapital: true))
        ] {
            try context.addEntry(
                for: DerivedKey.derive(seed: DiceKey.example.seed, recipe: recipe), diceKeyID: DiceKey.example.id)
        }
        return CatalogFile(
            records: try context.fetch(FetchDescriptor<DiceKeyRecord>()),
            entries: try context.fetch(FetchDescriptor<KeyEntry>()))
    }

    @Test("the file reads back as it was written, readable and compact alike")
    func roundTrip() throws {
        let file = try catalogWithKeys()
        #expect(file.keys.count == 2)
        #expect(try CatalogFile(json: file.json()) == file)
        #expect(try CatalogFile(json: file.json(readable: false)) == file)
        #expect(String(decoding: try file.json(), as: UTF8.self).contains("\n"))
    }

    @Test("the QR code's link carries the list without public keys")
    func importLink() throws {
        let file = try catalogWithKeys()
        let restored = try CatalogFile(importURL: try file.importURL)
        #expect(restored.diceKeys == file.diceKeys)
        #expect(restored.keys.map(\.name) == file.keys.map(\.name))
        #expect(restored.keys.allSatisfy { $0.publicKey == nil })
    }

    @Test("merging adds only what is missing")
    func merge() throws {
        let file = try catalogWithKeys()
        #expect(try file.merge(into: context) == (diceKeys: 0, keys: 0, unreadable: 0))
        let empty = ModelContext(try Catalog.container(syncing: false, inMemory: true))
        #expect(try file.merge(into: empty) == (diceKeys: 1, keys: 2, unreadable: 0))
        #expect(try empty.entries(for: DiceKey.example.id).map(\.name) == ["github", "nas"])
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
        #expect(try empty.entries(for: DiceKey.example.id).first?.publicKey == genuine)
    }

    @Test("a passphrase without its style, or a key without its DiceKey, is skipped")
    func skipsWhatCantBeRebuilt() throws {
        var file = try catalogWithKeys()
        file.keys = [
            CatalogFile.KeyItem(diceKey: DiceKey.example.id, kind: .passphrase, name: "x", style: nil),
            CatalogFile.KeyItem(diceKey: "unknown", kind: .ssh, name: "y", style: nil)
        ]
        let empty = ModelContext(try Catalog.container(syncing: false, inMemory: true))
        #expect(try file.merge(into: empty) == (diceKeys: 1, keys: 0, unreadable: 2))
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
        #expect(file.keys.map(\.name) == ["github"])
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
        #expect(try CatalogFile(importURL: try file.importURL).keys.map(\.name) == file.keys.map(\.name))
        let empty = ModelContext(try Catalog.container(syncing: false, inMemory: true))
        try file.merge(into: empty)
        #expect(Set(try empty.entries(for: DiceKey.example.id).map(\.name)) == Set(names))
    }
}
