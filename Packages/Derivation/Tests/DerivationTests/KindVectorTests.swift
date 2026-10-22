//
//  KindVectorTests.swift
//  DerivationTests
//
//  Fixtures/kinds.json is written by scripts/derive-kinds.py, an independent Python
//  implementation of the kinds, so these tests check the app against code it shares nothing
//  with but the word lists. A changed value means a changed key for someone.
//

import CryptoKit
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

struct DiceKeyIDVector: Codable, Sendable {
    let seed: String
    let id: String
}

/// The construction alone: HKDF-SHA256 with `info` = type || recipe.
struct HKDFVector: Codable, Sendable {
    let seed: String
    let type: String
    let recipe: String
    let length: Int
    let output: String
}

private struct KindFixture: Codable, Sendable {
    let origin: String
    let hkdf: [HKDFVector]
    let diceKeyIds: [DiceKeyIDVector]
    let cases: [KindVector]
}

private let kindFixture: KindFixture = {
    var url = URL(fileURLWithPath: #filePath)
    url.deleteLastPathComponent()
    url.append(path: "Fixtures/kinds.json")
    // swiftlint:disable:next force_try
    return try! JSONDecoder().decode(KindFixture.self, from: Data(contentsOf: url))
}()

private let kindCases = kindFixture.cases

@Test(arguments: kindCases)
func kindVector(_ vector: KindVector) throws {
    let kind = try #require(KeyKind(rawValue: vector.kind))
    let recipe = try KeyRecipe(kind: kind, name: vector.input, style: vector.style ?? .standard)
    #expect(recipe.name.utf8.elementsEqual(vector.name.utf8))
    #expect(recipe.json.utf8.elementsEqual(vector.recipe.utf8))
    #expect(try KeyRecipe(json: vector.recipe) == recipe)
    let key = DerivedKey.derive(seed: vector.seed, recipe: recipe)
    #expect(key.publicKey == vector.publicKey)
    #expect(key.fingerprint == vector.fingerprint)
    #expect(key.secret == vector.secret)
}

@Test func kindFixtureCoversEveryKind() {
    #expect(Set(kindCases.map(\.kind)) == Set(KeyKind.allCases.map(\.rawValue)))
}

@Test(arguments: kindFixture.hkdf)
func hkdfVector(_ vector: HKDFVector) throws {
    let type = try #require(DerivableType(rawValue: vector.type))
    let output = Engine.bytes(seed: vector.seed, type: type, recipe: vector.recipe, length: vector.length)
    #expect(output.map { String(format: "%02x", $0) }.joined() == vector.output)
}

@Test(arguments: kindFixture.diceKeyIds)
func diceKeyID(_ vector: DiceKeyIDVector) {
    #expect(DiceKeyID.derive(seed: vector.seed) == vector.id)
}

/// RFC 5869 appendix A.3: SHA-256 with no salt, as `Engine.bytes` uses it.
@Test func hkdfMatchesRFC5869WithoutSalt() {
    let key = HKDF<SHA256>.deriveKey(
        inputKeyMaterial: SymmetricKey(data: Data(repeating: 0x0B, count: 22)), info: Data(), outputByteCount: 42)
    let expected = "8da4e775a563c18f715f802a063c5a31b8a11f5c5ee1879ec3454e5f3c738d2d9d201395faa4b61a96c8"
    #expect(key.withUnsafeBytes { $0.map { String(format: "%02x", $0) }.joined() } == expected)
}
