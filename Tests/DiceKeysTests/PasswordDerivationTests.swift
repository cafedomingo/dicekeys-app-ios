//
//  PasswordDerivationTests.swift
//  DiceKeysTests
//
//  Kept from the deleted ApiRequestTests when the request API was removed: this one
//  guards derivation behaviour, not the API.
//

import Foundation
import Testing
import SeededCrypto
@testable import DiceKeys

@Suite("Password derivation")
struct PasswordDerivationTests {
    @Test("a recipe with lengthInChars 0 derives an empty password instead of throwing")
    func issue56PasswordCannotBeDerived() throws {
        let recipeJson = #"{"allow":[{"host":"*.exampl.com"}],"lengthInChars":0}"#
        let password = try Password.deriveFromSeed(withSeedString: "this string is seedy", recipe: recipeJson)
        // Upstream issue 56: deriving with lengthInChars 0 must not throw. The reference
        // implementation yields an empty password for that recipe (see golden-vectors.json).
        #expect(password.password.isEmpty)
    }
}
