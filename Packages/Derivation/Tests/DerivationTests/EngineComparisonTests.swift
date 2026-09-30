//
//  EngineComparisonTests.swift
//  DerivationTests
//
//  The Swift engine must produce the same JSON as the C++ for every fixture case. This is the
//  differential test the spec calls for; it goes when the C++ does, and the fixture tests
//  stay behind as the proof.
//

import Testing
@testable import Derivation

@Suite("Swift engine against the legacy engine")
struct EngineComparisonTests {
    @Test("every case derives identically", arguments: fixture.cases)
    func cases(vector: Vector) throws {
        let type = try #require(vector.derivableType)
        let swift = try SwiftEngine().derive(type, seed: vector.seed, recipe: vector.recipe)
        #expect(swift == vector.json)
        let legacy = try LegacyEngine().derive(type, seed: vector.seed, recipe: vector.recipe)
        #expect(swift == legacy)
    }

    @Test("legacy recipes are refused by the Swift engine", arguments: fixture.legacy)
    func legacy(vector: Vector) throws {
        let type = try #require(vector.derivableType)
        #expect(throws: DerivationError.self) { try SwiftEngine().derive(type, seed: vector.seed, recipe: vector.recipe) }
    }

    @Test("the consistent bits and words pair derives in Swift")
    func consistentPair() throws {
        let json = try SwiftEngine().derive(.password, seed: fixture.diceKeys[0].seed, recipe: #"{"lengthInBits":90,"lengthInWords":10}"#)
        #expect(json.hasPrefix(#"{"password":"10-"#))
    }

    @Test("the empty recipe and the empty object differ")
    func emptyRecipes() throws {
        let empty = try SwiftEngine().derive(.secret, seed: fixture.diceKeys[0].seed, recipe: "")
        let object = try SwiftEngine().derive(.secret, seed: fixture.diceKeys[0].seed, recipe: "{}")
        #expect(empty != object)
        #expect(!empty.contains("recipe"))
        #expect(object.contains(##""recipe":"{}""##))
    }

    @Test("JSON values are escaped as nlohmann escapes them")
    func escaping() {
        let expected = "{\"a\":\"q\\\"b\\\\s/\\u0001\u{7f}é\",\"b\":\"x\"}"
        #expect(ReferenceJSON.object([(key: "b", value: "x"), (key: "a", value: "q\"b\\s/\u{01}\u{7f}é")]) == expected)
    }
}
