//
//  RecoveryCodeTests.swift
//  DiceKeyVaultTests
//

import Derivation
import Foundation
import KeyFormats
import SwiftData
import Testing

@testable import DiceKeyVault

@MainActor
struct RecoveryCodeTests {
    private func emptyContext() throws -> ModelContext {
        ModelContext(try Catalog.container(syncing: false, inMemory: true))
    }

    private func payload(_ edit: (inout [String: Any]) -> Void) throws -> String {
        let fixture = try Fixture.text("recovery-v1.txt")
        let base64 = String(fixture.dropFirst(RecoveryCode.prefix.count))
        let data = try #require(Data(base64URLEncoded: base64))
        var json = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        edit(&json)
        return RecoveryCode.prefix + (try JSONSerialization.data(withJSONObject: json)).base64URLEncodedString
    }

    @Test("the v1 recovery code decodes to the example DiceKey and its keys")
    func fixtureDecodes() throws {
        let code = try RecoveryCode(payload: Fixture.text("recovery-v1.txt"))
        #expect(code.diceKey == DiceKey.example)
        #expect(code.catalog == CatalogFormatV1Tests.expected)
    }

    @Test("today's encoder writes the v1 recovery code byte for byte")
    func fixtureEncodes() throws {
        let code = try RecoveryCode(payload: Fixture.text("recovery-v1.txt"))
        #expect(try code.payload == Fixture.text("recovery-v1.txt"))
    }

    @Test("restoring adds the DiceKey and its keys, without public keys")
    func restore() throws {
        let context = try emptyContext()
        let diceKey = try RecoveryCode(payload: Fixture.text("recovery-v1.txt")).restore(into: context)
        #expect(diceKey.id == DiceKey.example.id)
        #expect(try context.record(for: diceKey.id)?.name == "Example")
        #expect(try context.entries(for: diceKey.id).count == 7)
        #expect(try context.entries(for: diceKey.id).allSatisfy { $0.publicKey == nil })
    }

    @Test("restoring onto a device that has the DiceKey keeps its name and adds only what is missing")
    func restoreKeepsWhatIsThere() throws {
        let context = try emptyContext()
        try context.recordIfNew(DiceKey.example)
        try context.record(for: DiceKey.example.id)?.name = "Mine"
        let github = try KeyRecipe(kind: .ssh, name: "github")
        try context.addEntry(
            for: DerivedKey.derive(seed: DiceKey.example.seed, recipe: github), diceKeyID: DiceKey.example.id)
        try RecoveryCode(payload: Fixture.text("recovery-v1.txt")).restore(into: context)
        #expect(try context.record(for: DiceKey.example.id)?.name == "Mine")
        let entries = try context.fetch(FetchDescriptor<KeyEntry>())
        #expect(entries.count == 7)
        #expect(entries.count { $0.recipe == github } == 1)
    }

    @Test("a code made from the DiceKey held turned restores to the same id and keys")
    func turnedDiceKeyRestoresTheSame() throws {
        let fixture = try RecoveryCode(payload: Fixture.text("recovery-v1.txt"))
        let turned = DiceKey.example.turnedClockwise()
        let payload = try payload { $0["diceKey"] = turned.text }
        let context = try emptyContext()
        let restored = try RecoveryCode(payload: payload).restore(into: context)
        #expect(restored.id == DiceKey.example.id)
        #expect(try context.entries(for: DiceKey.example.id).count == fixture.catalog.keys.count)
    }

    @Test("a key a later version wrote still lets the sheet restore its DiceKey and the other keys")
    func unknownKeyStillRestores() throws {
        let code = try RecoveryCode(
            payload: try payload { json in
                var keys = json["keys"] as? [[String: Any]] ?? []
                keys.append(["diceKey": DiceKey.example.id, "kind": "pgp", "name": "mail"])
                json["keys"] = keys
            })
        #expect(code.diceKey == DiceKey.example)
        #expect(code.catalog.unreadableKeys == 1)
        #expect(!code.catalog.keys.isEmpty)
    }

    @Test("a list link, a tampered id, short faces or a newer version is refused")
    func refusals() throws {
        #expect(throws: CatalogFile.Failure.notACatalog) {
            try RecoveryCode(payload: Fixture.text("catalog-link-v1.txt"))
        }
        let otherID = try payload {
            $0["diceKeys"] = [["id": "AAAAAAAAAAAAAAAAAAAAAA", "name": "Example", "centerFace": "M1t"]]
        }
        #expect(throws: CatalogFile.Failure.notACatalog) { try RecoveryCode(payload: otherID) }
        let short = try payload { $0["diceKey"] = String(DiceKey.example.text.dropLast()) }
        #expect(throws: CatalogFile.Failure.notACatalog) { try RecoveryCode(payload: short) }
        let newer = try payload { $0["v"] = 2 }
        #expect(throws: CatalogFile.Failure.newerVersion(2)) { try RecoveryCode(payload: newer) }
        #expect(throws: CatalogFile.Failure.notACatalog) { try RecoveryCode(payload: "DKV1R:!!") }
        let fixture = try Fixture.text("recovery-v1.txt")
        #expect(throws: (any Error).self) { try CatalogFile(importURL: #require(URL(string: fixture))) }
    }
}
