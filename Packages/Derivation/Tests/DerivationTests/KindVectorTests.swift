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
    let postQuantum: PostQuantumVector?
}

/// A default key, which has no name and so no input or style.
struct DefaultVector: Codable, Sendable, CustomTestStringConvertible {
    var testDescription: String { "\(kind) \(seed.prefix(6))" }
    let seed: String
    let kind: String
    let recipe: String
    let type: String
    let publicKey: String?
    let fingerprint: String?
    let secret: String
    let postQuantum: PostQuantumVector?
}

/// An age key's post-quantum identity, derived from the key's own recipe as a Secret.
struct PostQuantumVector: Codable, Sendable {
    let type: String
    let publicKey: String
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
    let defaults: [DefaultVector]
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
    #expect(recipe.name?.utf8.elementsEqual(vector.name.utf8) == true)
    #expect(recipe.json.utf8.elementsEqual(vector.recipe.utf8))
    #expect(try KeyRecipe(json: vector.recipe) == recipe)
    let key = DerivedKey.derive(seed: vector.seed, recipe: recipe)
    #expect(key.publicKey == vector.publicKey)
    #expect(kind.hasPublicKey == (vector.publicKey != nil))
    #expect(key.fingerprint == vector.fingerprint)
    #expect(key.secret == vector.secret)
    #expect(key.postQuantum?.recipient == vector.postQuantum?.publicKey)
    #expect(key.postQuantum?.identity == vector.postQuantum?.secret)
    if let postQuantum = vector.postQuantum {
        #expect(postQuantum.type == DerivableType.mlkem768x25519.rawValue)
    }
}

@Test(arguments: kindFixture.defaults)
func defaultVector(_ vector: DefaultVector) throws {
    let recipe = try #require(KeyRecipe.defaults.first { $0.kind.rawValue == vector.kind })
    #expect(recipe.json.utf8.elementsEqual(vector.recipe.utf8))
    let key = DerivedKey.derive(seed: vector.seed, recipe: recipe)
    #expect(key.publicKey == vector.publicKey)
    #expect(key.fingerprint == vector.fingerprint)
    #expect(key.secret == vector.secret)
    #expect(key.postQuantum?.recipient == vector.postQuantum?.publicKey)
    #expect(key.postQuantum?.identity == vector.postQuantum?.secret)
    if let postQuantum = vector.postQuantum {
        #expect(postQuantum.type == DerivableType.mlkem768x25519.rawValue)
    }
}

@Test func defaultFixtureCoversEveryDefault() {
    let kinds = Set(KeyRecipe.defaults.map(\.kind.rawValue))
    #expect(Set(kindFixture.defaults.map(\.kind)) == kinds)
    #expect(kindFixture.defaults.count == kinds.count * Set(kindFixture.defaults.map(\.seed)).count)
    #expect(kindFixture.defaults.allSatisfy { ($0.kind == KeyKind.age.rawValue) == ($0.postQuantum != nil) })
}

@Test func kindFixtureCoversEveryKind() {
    #expect(Set(kindCases.map(\.kind)) == Set(KeyKind.allCases.map(\.rawValue)))
    #expect(kindCases.allSatisfy { ($0.kind == KeyKind.age.rawValue) == ($0.postQuantum != nil) })
}

/// The example identity and recipient in the age specification (https://c2sp.org/age), a pair
/// `age-keygen -y` agrees on. The seed is the identity's Bech32 data, decoded separately.
@Test func agePostQuantumMatchesTheSpecExample() throws {
    var url = URL(fileURLWithPath: #filePath)
    url.deleteLastPathComponent()
    url.append(path: "Fixtures/age-pq-spec.txt")
    let lines = try String(contentsOf: url, encoding: .utf8).split(separator: "\n").map(String.init)
    let seed = try #require(Data(hexString: "31bda90fbf9fccdde5cfc0ed5a0378c5ea67ea193d7938b03b8c5dabb9a67de3"))
    let key = try Age.postQuantum(seed: seed)
    #expect(key.identity == lines[0])
    #expect(key.recipient == lines[1])
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
