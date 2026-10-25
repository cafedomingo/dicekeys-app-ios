//
//  CompatibilityTests.swift
//  DiceKeyVaultTests
//
//  What this app writes outside itself must read the same in every later version: the
//  store, synced through CloudKit to devices on other versions, and the names that find it.
//  Derived keys, the DiceKey id, the exported file and paper are pinned by their own fixtures
//  (kinds.json, CatalogFormatV1Tests, PaperFormatV2Tests). A failure here means a change breaks
//  data already written.
//

import Foundation
import SwiftData
import Testing

@testable import DiceKeyVault

struct CompatibilityTests {
    /// Attributes may be added, with a default; one recorded here may never be renamed,
    /// removed or retyped, because earlier versions and other devices still hold it.
    @Test("the store keeps every attribute it has written, with its type")
    func storeAttributes() throws {
        let recorded = [
            "DiceKeyRecord": [
                "diceKeyID": "String", "name": "String", "centerFace": "String", "created": "Date"
            ],
            "KeyEntry": [
                "diceKeyID": "String", "recipeJSON": "String", "publicKey": "Optional<String>", "created": "Date"
            ]
        ]
        let schema = try Catalog.container(syncing: false, inMemory: true).schema
        for (entity, attributes) in recorded {
            let stored = schema.entitiesByName[entity]?.attributesByName.mapValues { String(describing: $0.valueType) }
            for (name, type) in attributes {
                #expect(stored?[name] == type, "\(entity).\(name)")
            }
        }
    }

    @Test("the names that find stored data never change")
    func storedNames() {
        #expect(Bundle.main.bundleIdentifier == "com.cafedomingo.dicekeys")
        #expect(Catalog.storeName == "Catalog")
        #expect(Catalog.syncSettingKey == "syncsCatalogWithICloud")
        #expect(CatalogFile.urlScheme == "dicekeyvault")
        #expect(RecoveryCode.prefix == "DKVR:")
        #expect(PaperPayload.version == 2)
    }
}
