//
//  EmptyRecipeTests.swift
//  SeededCryptoTests
//
//  lib-seeded leaves "recipe" (and "unsealingInstructions") out of its JSON when they are
//  empty, so the Swift side must read them as optional.
//

import Foundation
import Testing
@testable import SeededCrypto

/// `DiceKey.Example`'s seed, the one every fixture entry that needs a DiceKey uses.
let exampleDiceKeySeed = "A1tB2rC3bD4lE5tF6rG1bH2lI3tJ4rK5bL6lM1tN2rO3bP4lR5tS6rT1bU2lV3tW4rX5bY6lZ1t"

@Suite("Empty recipes")
struct EmptyRecipeTests {
    @Test("an empty recipe derives and decodes")
    func emptyRecipeDerives() throws {
        let seed = exampleDiceKeySeed
        #expect(try Secret.deriveFromSeed(withSeedString: seed, recipe: "").recipe == "")
        #expect(try Password.deriveFromSeed(withSeedString: seed, recipe: "").recipe == "")
        #expect(try SymmetricKey.deriveFromSeed(withSeedString: seed, recipe: "").recipe == "")
    }

    @Test("a message sealed with an empty recipe round-trips")
    func emptyRecipeSeals() throws {
        let key = try SymmetricKey.deriveFromSeed(withSeedString: exampleDiceKeySeed, recipe: "")
        let sealed = try key.seal(withMessage: "hello")
        #expect(sealed.recipe == "")
        #expect(sealed.unsealingInstructions == "")
        #expect(try key.unseal(withPackagedSealedMessage: sealed) == Data("hello".utf8))
    }
}
