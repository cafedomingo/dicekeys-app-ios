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

@Suite("Empty recipes")
struct EmptyRecipeTests {
    @Test("an empty recipe derives and decodes")
    func emptyRecipeDerives() throws {
        let seed = fixture.exampleDiceKeySeed
        #expect(try Secret.deriveFromSeed(withSeedString: seed, recipe: "").recipe == "")
        #expect(try Password.deriveFromSeed(withSeedString: seed, recipe: "").recipe == "")
        #expect(try SymmetricKey.deriveFromSeed(withSeedString: seed, recipe: "").recipe == "")
    }

    @Test("a message sealed with an empty recipe round-trips")
    func emptyRecipeSeals() throws {
        let key = try SymmetricKey.deriveFromSeed(withSeedString: fixture.exampleDiceKeySeed, recipe: "")
        let sealed = try key.seal(withMessage: "hello")
        #expect(sealed.recipe == "")
        #expect(sealed.unsealingInstructions == "")
        #expect(try key.unseal(withPackagedSealedMessage: sealed) == Data("hello".utf8))
    }
}
