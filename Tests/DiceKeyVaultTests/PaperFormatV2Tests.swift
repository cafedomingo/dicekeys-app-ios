//
//  PaperFormatV2Tests.swift
//  DiceKeyVaultTests
//

import Derivation
import Foundation
import Testing

@testable import DiceKeyVault

/// Version 2 is printed on paper, so it must read the same in every later version of the app.
/// If one of these fails, the change breaks paper already printed: change the code, never the
/// fixtures.
@MainActor
struct PaperFormatV2Tests {
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

    @Test("the v2 link decodes to exactly this DiceKey and these keys")
    func linkFixtureDecodes() throws {
        let file = try CatalogFile(importURL: #require(URL(string: Fixture.text("catalog-link-v2.txt"))))
        #expect(file.diceKeys == [CatalogFile.DiceKeyItem(id: Self.id, name: "Example", centerFace: "M1t")])
        #expect(file.keys.map(\.recipe) == (try Self.expectedRecipes))
        #expect(file.keys.allSatisfy { $0.diceKey == Self.id && $0.publicKey == nil })
        #expect(file == Self.expected)
    }

    @Test("the v2 recovery code decodes to the example DiceKey and exactly these keys")
    func recoveryFixtureDecodes() throws {
        let code = try RecoveryCode(payload: Fixture.text("recovery-v2.txt"))
        #expect(code.diceKey == DiceKey.example)
        #expect(code.catalog.keys.map(\.recipe) == (try Self.expectedRecipes))
        #expect(code.catalog == Self.expected)
    }

    @Test("the link reads the same after URL parsing passes it on")
    func linkSurvivesURLParsing() throws {
        let catalog = try CatalogFile(importURL: #require(URL(string: Fixture.text("catalog-link-v2.txt"))))
        let link = try catalog.importURL.absoluteString
        #expect(!link.contains("%"))
        #expect(try CatalogFile(importURL: #require(URL(string: link))) == catalog)
    }

    @Test("the fixtures start with the link's URL and the recovery code's prefix")
    func fixturesStartAsExpected() throws {
        #expect(try Fixture.text("catalog-link-v2.txt").hasPrefix("dicekeyvault://import?catalog="))
        #expect(try Fixture.text("recovery-v2.txt").hasPrefix("DKVR:"))
    }
}
