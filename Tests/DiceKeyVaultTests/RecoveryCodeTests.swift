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
        let fixture = try Fixture.text("recovery-v2.txt")
        let data = try PaperPayload.unpack(String(fixture.dropFirst(RecoveryCode.prefix.count)))
        var json = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        edit(&json)
        return RecoveryCode.prefix + (try PaperPayload.pack(JSONSerialization.data(withJSONObject: json)))
    }

    @Test("the v2 recovery code decodes to the example DiceKey and its keys")
    func fixtureDecodes() throws {
        let code = try RecoveryCode(payload: Fixture.text("recovery-v2.txt"))
        #expect(code.diceKey == DiceKey.example)
        #expect(code.catalog == PaperFormatV2Tests.expected)
    }

    @Test("a recovery code reads back as the code it writes")
    func payloadRoundTrips() throws {
        let code = try RecoveryCode(payload: Fixture.text("recovery-v2.txt"))
        #expect(try RecoveryCode(payload: code.payload) == code)
    }

    @Test("restoring adds the DiceKey and its keys, without public keys")
    func restore() throws {
        let context = try emptyContext()
        let diceKey = try RecoveryCode(payload: Fixture.text("recovery-v2.txt")).restore(into: context)
        #expect(diceKey.id == DiceKey.example.id)
        #expect(try context.record(for: diceKey.id)?.name == "Example")
        #expect(try context.entries(for: diceKey.id).count == 9)
        #expect(try context.entries(for: diceKey.id).allSatisfy { $0.publicKeys.isEmpty })
    }

    @Test("restoring a DiceKey records it with the default keys")
    func restoreAddsDefaults() throws {
        let context = try emptyContext()
        let diceKey = try RecoveryCode(payload: Fixture.text("recovery-v2.txt")).restore(into: context)
        #expect(try context.entries(for: diceKey.id).compactMap(\.recipe).filter(\.isDefault) == KeyRecipe.defaults)
    }

    @Test("the code and its list carry the default keys, then the named ones")
    func codeCarriesDefaults() throws {
        let context = try emptyContext()
        try context.recordIfNew(DiceKey.example)
        let github = try KeyRecipe(kind: .ssh, name: "github")
        try context.addEntry(
            for: DerivedKey.derive(seed: DiceKey.example.seed, recipe: github), diceKeyID: DiceKey.example.id)
        let record = try #require(try context.record(for: DiceKey.example.id))
        let code = try RecoveryCode(
            diceKey: .example, record: record, entries: try context.entries(for: DiceKey.example.id))
        #expect(code.catalog.keys.map(\.recipe) == KeyRecipe.defaults + [github])
        #expect(try RecoveryCode(payload: code.payload) == code)
    }

    @Test("restoring onto a device that has the DiceKey keeps its name and adds only what is missing")
    func restoreKeepsWhatIsThere() throws {
        let context = try emptyContext()
        try context.recordIfNew(DiceKey.example)
        try context.record(for: DiceKey.example.id)?.name = "Mine"
        let github = try KeyRecipe(kind: .ssh, name: "github")
        try context.addEntry(
            for: DerivedKey.derive(seed: DiceKey.example.seed, recipe: github), diceKeyID: DiceKey.example.id)
        try RecoveryCode(payload: Fixture.text("recovery-v2.txt")).restore(into: context)
        #expect(try context.record(for: DiceKey.example.id)?.name == "Mine")
        let entries = try context.fetch(FetchDescriptor<KeyEntry>())
        #expect(entries.count == 9)
        #expect(entries.count { $0.recipe == github } == 1)
    }

    @Test("a code made from the DiceKey held turned restores to the same id and keys")
    func turnedDiceKeyRestoresTheSame() throws {
        let fixture = try RecoveryCode(payload: Fixture.text("recovery-v2.txt"))
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
                keys.append(["kind": "pgp", "name": "mail"])
                json["keys"] = keys
            })
        #expect(code.diceKey == DiceKey.example)
        #expect(code.catalog.unreadableKeys == 1)
        #expect(!code.catalog.keys.isEmpty)
    }

    @Test("a list link, a tampered id, missing or short faces or a newer version is refused")
    func refusals() throws {
        #expect(throws: CatalogFile.Failure.notACatalog) {
            try RecoveryCode(payload: Fixture.text("catalog-link-v2.txt"))
        }
        let otherID = try payload { $0["id"] = "AAAAAAAAAAAAAAAAAAAAAA" }
        #expect(throws: CatalogFile.Failure.notACatalog) { try RecoveryCode(payload: otherID) }
        let noFaces = try payload { $0["diceKey"] = nil }
        #expect(throws: CatalogFile.Failure.notACatalog) { try RecoveryCode(payload: noFaces) }
        let short = try payload { $0["diceKey"] = String(DiceKey.example.text.dropLast()) }
        #expect(throws: CatalogFile.Failure.notACatalog) { try RecoveryCode(payload: short) }
        let newer = try payload { $0["v"] = 3 }
        #expect(throws: CatalogFile.Failure.newerVersion(3)) { try RecoveryCode(payload: newer) }
        #expect(throws: CatalogFile.Failure.notACatalog) { try RecoveryCode(payload: "DKVR:!!") }
        let fixture = try Fixture.text("recovery-v2.txt")
        #expect(throws: (any Error).self) { try CatalogFile(importURL: #require(URL(string: fixture))) }
    }
}
