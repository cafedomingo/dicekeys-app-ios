//
//  KindVectorTests.swift
//  DerivationTests
//
//  Fixtures/kinds.json is written by scripts/derive-kinds.py, an independent Python
//  implementation of the kinds, so these tests check the app against code it shares nothing
//  with but the word lists. A changed value means a changed key for someone.
//

import Foundation
import Testing

@testable import Derivation
@testable import KeyFormats

struct KindVector: Codable, Sendable, CustomTestStringConvertible {
    var testDescription: String { "\(kind) \(name) \(seed.prefix(6))" }
    let seed: String
    let kind: String
    let input: String
    let name: String
    let style: PassphraseStyle?
    let recipe: String
    let type: String
    let publicKey: String?
    let fingerprint: String?
    let secret: String
}

private struct KindFixture: Codable, Sendable {
    let origin: String
    let cases: [KindVector]
}

private let kindCases: [KindVector] = {
    var url = URL(fileURLWithPath: #filePath)
    url.deleteLastPathComponent()
    url.append(path: "Fixtures/kinds.json")
    // swiftlint:disable:next force_try
    return try! JSONDecoder().decode(KindFixture.self, from: Data(contentsOf: url)).cases
}()

@Test(arguments: kindCases)
func kindVector(_ vector: KindVector) throws {
    let kind = try #require(KeyKind(rawValue: vector.kind))
    let recipe = try KeyRecipe(kind: kind, name: vector.input, style: vector.style ?? .standard)
    #expect(recipe.name == vector.name)
    #expect(recipe.json == vector.recipe)
    #expect(kind.derivableType.rawValue == vector.type)
    let key = DerivedKey.derive(seed: vector.seed, recipe: recipe)
    #expect(key.publicKey == vector.publicKey)
    #expect(key.fingerprint == vector.fingerprint)
    #expect(key.secret == vector.secret)
}

@Test func kindFixtureCoversEveryKind() {
    #expect(Set(kindCases.map(\.kind)) == Set(KeyKind.allCases.map(\.rawValue)))
}
