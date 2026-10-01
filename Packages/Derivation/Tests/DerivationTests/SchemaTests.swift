//
//  SchemaTests.swift
//  DerivationTests
//

import Foundation
import Testing
@testable import Derivation

private typealias JSONObject = [String: Any]

/// Reads docs/recipe-schema.json from the source tree, not the test bundle.
private func loadSchema() throws -> JSONObject {
    var url = URL(fileURLWithPath: #filePath)
    for _ in 0..<5 { url.deleteLastPathComponent() }
    url.append(path: "docs/recipe-schema.json")
    return try #require(try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? JSONObject)
}

private func properties(of schema: JSONObject) throws -> [String: JSONObject] {
    try #require(schema["properties"] as? [String: JSONObject])
}

/// A JSON integer as JSONSerialization returns it: a number that is neither a boolean nor a fraction.
private func integer(_ value: Any) -> Int? {
    guard let number = value as? NSNumber,
        CFGetTypeID(number) != CFBooleanGetTypeID(),
        !CFNumberIsFloatType(number)
    else { return nil }
    return number.intValue
}

@Suite("The published recipe schema")
struct SchemaTests {
    @Test("it is a draft 2020-12 schema for an object that allows unknown fields")
    func shape() throws {
        let schema = try loadSchema()
        #expect(schema["$schema"] as? String == "https://json-schema.org/draft/2020-12/schema")
        #expect(schema["type"] as? String == "object")
        #expect(schema["additionalProperties"] as? Bool == true)
        #expect((schema["description"] as? String)?.contains("salt") == true)
    }

    @Test("it names every field the parser reads, with the parser's values and bounds")
    func fields() throws {
        let properties = try properties(of: loadSchema())
        func allowed(_ name: String) -> Set<String> { Set(properties[name]?["enum"] as? [String] ?? []) }
        #expect(allowed("type") == Set(DerivableType.allCases.map(\.rawValue)))
        #expect(allowed("algorithm") == ["XSalsa20Poly1305", "X25519", "Ed25519"])
        #expect(allowed("hashFunction") == [HashFunction.blake2b.rawValue])
        #expect(allowed("wordList") == Set(WordList.allCases.map(\.rawValue)))
        for name in ["lengthInBytes", "lengthInChars", "lengthInBits", "lengthInWords", "#"] {
            #expect(properties[name]?["type"] as? String == "integer", "\(name)")
            #expect(properties[name]?["minimum"] as? Int == 1, "\(name)")
        }
        #expect(properties["lengthInBytes"]?["maximum"] as? Int == Recipe.maximumLengthInBytes)
        #expect(properties["lengthInWords"]?["maximum"] as? Int == Recipe.maximumLengthInWords)
        #expect(properties["lengthInChars"]?["maximum"] == nil)
        #expect(properties["lengthInBits"]?["maximum"] == nil)
        #expect(properties["purpose"]?["type"] as? String == "string")
    }

    @Test("every object recipe in the fixture has values the schema allows")
    func fixtureRecipesConform() throws {
        let properties = try properties(of: loadSchema())
        for text in fixture.cases.map(\.recipe) where !text.isEmpty {
            let recipe = try #require(try JSONSerialization.jsonObject(with: Data(text.utf8)) as? JSONObject, "\(text)")
            for (name, value) in recipe {
                guard let definition = properties[name] else { continue }
                if let allowed = definition["enum"] as? [String] {
                    #expect(allowed.contains(value as? String ?? ""), "\(name) in \(text)")
                }
                if definition["type"] as? String == "integer" {
                    let number = try #require(integer(value), "\(name) in \(text)")
                    if let minimum = definition["minimum"] as? Int { #expect(number >= minimum, "\(name) in \(text)") }
                    if let maximum = definition["maximum"] as? Int { #expect(number <= maximum, "\(name) in \(text)") }
                }
                if definition["type"] as? String == "string" {
                    #expect(value is String, "\(name) in \(text)")
                }
            }
        }
    }
}
