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
    let algorithms: [AlgorithmVector]
}

/// A default key, which has no name and so no input or style.
struct DefaultVector: Codable, Sendable, CustomTestStringConvertible {
    var testDescription: String { "\(kind) \(seed.prefix(6))" }
    let seed: String
    let kind: String
    let recipe: String
    let algorithms: [AlgorithmVector]
}

/// One algorithm's key, derived from the recipe under the algorithm's own type.
struct AlgorithmVector: Codable, Sendable {
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
    try expectAlgorithms(vector.algorithms, of: kind, seed: vector.seed, recipe: recipe)
}

@Test(arguments: kindFixture.defaults)
func defaultVector(_ vector: DefaultVector) throws {
    let recipe = try #require(KeyRecipe.defaults.first { $0.kind.rawValue == vector.kind })
    #expect(recipe.json.utf8.elementsEqual(vector.recipe.utf8))
    try expectAlgorithms(vector.algorithms, of: recipe.kind, seed: vector.seed, recipe: recipe)
}

/// The kind's algorithms are the vector's, matched by type, and each key holds the vector's
/// values. Order is emphasis only and may change (`derivation.md`), so it is not checked
/// here; `eachKindsAlgorithmsInOrder` holds this app's.
private func expectAlgorithms(
    _ expected: [AlgorithmVector], of kind: KeyKind, seed: String, recipe: KeyRecipe
) throws {
    let key = DerivedKey.derive(seed: seed, recipe: recipe)
    let types = Set(expected.map(\.type))
    #expect(types.count == expected.count)
    #expect(Set(kind.algorithms.map(\.rawValue)) == types)
    #expect(kind.algorithms.count == expected.count)
    #expect(Set(key.algorithms.map(\.type.rawValue)) == types)
    #expect(key.algorithms.count == expected.count)
    for vector in expected {
        let derived = try #require(key.algorithms.first { $0.type.rawValue == vector.type }, "\(vector.type)")
        #expect(derived.publicKey == vector.publicKey, "\(vector.type)")
        #expect(derived.fingerprint == vector.fingerprint, "\(vector.type)")
        #expect(derived.secret == vector.secret, "\(vector.type)")
    }
    let publicKeys = expected.compactMap { a in a.publicKey.map { (a.type, $0) } }
    #expect(key.publicKeys == Dictionary(uniqueKeysWithValues: publicKeys))
    #expect(expected.allSatisfy { ($0.publicKey != nil) == kind.hasPublicKey })
}

@Test func eachKindsAlgorithmsInOrder() {
    #expect(
        KeyKind.allCases.map(\.algorithms)
            == [[.ed25519], [.x25519], [.x25519, .mlkem768x25519], [.passphrase], [.bip39]])
    #expect(KeyKind.allCases.allSatisfy { Set($0.algorithms).count == $0.algorithms.count })
}

@Test func defaultFixtureCoversEveryDefault() {
    let kinds = Set(KeyRecipe.defaults.map(\.kind.rawValue))
    #expect(Set(kindFixture.defaults.map(\.kind)) == kinds)
    #expect(kindFixture.defaults.count == kinds.count * Set(kindFixture.defaults.map(\.seed)).count)
}

@Test func kindFixtureCoversEveryKind() {
    #expect(Set(kindCases.map(\.kind)) == Set(KeyKind.allCases.map(\.rawValue)))
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
    #expect(key.type == .mlkem768x25519)
    #expect(key.secret == lines[0])
    #expect(key.publicKey == lines[1])
    #expect(key.fingerprint == nil)
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
