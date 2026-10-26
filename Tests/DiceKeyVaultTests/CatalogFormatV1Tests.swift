//
//  CatalogFormatV1Tests.swift
//  DiceKeyVaultTests
//

import Derivation
import Foundation
import SwiftData
import Testing

@testable import DiceKeyVault

/// Version 1 is printed on paper, so it must read the same in every later version of the app.
/// If one of these fails, the change breaks paper already printed: change the code, never the
/// fixtures.
@MainActor
struct CatalogFormatV1Tests {
    private static let id = "FDWCWOqOuLX6kRVI9K31_A"

    private static var expectedRecipes: [KeyRecipe] {
        get throws {
            [
                try KeyRecipe(kind: .ssh, name: "🧨 & 日本語"),
                try KeyRecipe(kind: .age, name: "backups"),
                try KeyRecipe(kind: .passphrase, name: "bank", style: .memorable(words: 6, digitsAndUppercase: true)),
                try KeyRecipe(kind: .wallet, name: "cold"),
                try KeyRecipe(kind: .ssh, name: "github"),
                try KeyRecipe(kind: .wireguard, name: "home"),
                try KeyRecipe(kind: .passphrase, name: "nas", style: .random(length: 24, symbols: false))
            ]
        }
    }

    static let expected = CatalogFile(
        diceKeys: [CatalogFile.DiceKeyItem(id: id, name: "Example", centerFace: "M1t")],
        // swiftlint:disable:next force_try
        keys: try! expectedRecipes.map { CatalogFile.KeyItem(diceKey: id, recipe: $0) })

    @Test("the v1 file decodes to exactly these DiceKeys and keys")
    func fileDecodes() throws {
        var file = try CatalogFile(json: Fixture.data("catalog-v1.json"))
        #expect(file.diceKeys == Self.expected.diceKeys)
        let withPublicKeys = file.keys.filter { $0.recipe.kind != .passphrase && $0.recipe.kind != .wallet }
        #expect(withPublicKeys.allSatisfy { $0.publicKey != nil })
        file.keys = file.keys.map {
            var key = $0
            key.publicKey = nil
            return key
        }
        #expect(file.keys == Self.expected.keys)
    }

    @Test("the v1 link decodes to exactly these DiceKeys and keys")
    func linkDecodes() throws {
        let file = try CatalogFile(importURL: #require(URL(string: Fixture.text("catalog-link-v1.txt"))))
        #expect(file == Self.expected)
    }

    @Test("today's encoder writes the v1 link byte for byte")
    func linkEncodes() throws {
        #expect(try Self.expected.importURL.absoluteString == Fixture.text("catalog-link-v1.txt"))
    }

    @Test("today's encoder writes the same v1 file, ignoring whitespace")
    func fileEncodes() throws {
        let fixture = try Fixture.data("catalog-v1.json")
        let written = try CatalogFile(json: fixture).json()
        #expect(
            try JSONSerialization.jsonObject(with: fixture) as? NSDictionary
                == JSONSerialization.jsonObject(with: written) as? NSDictionary)
    }

    @Test("merging the v1 link makes exactly these recipes, and the default keys")
    func linkMakesTheseRecipes() throws {
        let context = ModelContext(try Catalog.container(syncing: false, inMemory: true))
        try Self.expected.merge(into: context)
        #expect(
            Set(try context.entries(for: DiceKey.example.id).compactMap(\.recipe))
                == Set(try Self.expectedRecipes + KeyRecipe.defaults))
    }
}
