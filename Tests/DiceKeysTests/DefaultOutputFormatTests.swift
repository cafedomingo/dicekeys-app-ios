//
//  DefaultOutputFormatTests.swift
//  DiceKeysTests
//
//  The derive screen opens on the output a recipe's users expect: the password itself for
//  passwords, OpenSSH/OpenPGP for those signing keys, BIP39 for a wallet seed. It used to
//  open on JSON because the default was chosen before the value had been derived.
//

import Testing
@testable import DiceKeys

@MainActor
struct DefaultOutputFormatTests {
    private func template(_ name: String) throws -> DerivationRecipe {
        try #require(derivationRecipeTemplates.first { $0.name == name })
    }

    private func defaultFormat(_ recipe: DerivationRecipe) throws -> DerivedValueView {
        recipe.defaultOutputFormat(for: try recipe.derivedValue(diceKey: DiceKey.Example))
    }

    @Test func passwordRecipesOpenOnThePassword() throws {
        #expect(try defaultFormat(template("1Password")) == .Password)
    }

    @Test func sshOpensOnOpenSSH() throws {
        #expect(try defaultFormat(template("SSH")) == .OpenSSHPrivateKey)
    }

    @Test func pgpOpensOnOpenPGP() throws {
        #expect(try defaultFormat(template("PGP")) == .OpenPGPPrivateKey)
    }

    @Test func walletSeedOpensOnBIP39() throws {
        #expect(try defaultFormat(template("Cryptocurrency wallet seed")) == .BIP39)
    }
}
