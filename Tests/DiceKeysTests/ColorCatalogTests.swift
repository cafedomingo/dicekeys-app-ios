//
//  ColorCatalogTests.swift
//  DiceKeysTests
//
//  The catalog's folders are a contract. Depiction and Camera colors stand for things that
//  look the same whatever the appearance, so they carry one value; Interface colors sit on
//  the system background, so each must answer for dark.
//

import Foundation
import Testing

/// The parts of a color set's `Contents.json` the contract is about.
private struct ColorSet: Decodable {
    struct Entry: Decodable {
        let appearances: [CatalogAppearance]?
        let color: CatalogColor?
    }
    let colors: [Entry]
}

private struct CatalogColor: Decodable {
    let reference: String?
}

struct ColorCatalogTests {
    private static func colorSets(in namespace: String) throws -> [(name: String, contents: ColorSet)] {
        try AssetCatalogSource.entries(ColorSet.self, in: "Colors.xcassets/\(namespace)", suffix: ".colorset")
    }

    @Test("fixed namespaces carry exactly one value", arguments: ["Depiction", "Camera"])
    func fixedNamespacesHaveOneValue(namespace: String) throws {
        let sets = try Self.colorSets(in: namespace)
        #expect(!sets.isEmpty)
        for (name, set) in sets {
            #expect(set.colors.count == 1, "\(namespace)/\(name) must not vary by appearance")
            #expect(set.colors.first?.appearances == nil, "\(namespace)/\(name) must not vary by appearance")
        }
    }

    @Test("interface colors answer for dark")
    func interfaceColorsAnswerForDark() throws {
        let sets = try Self.colorSets(in: "Interface")
        #expect(!sets.isEmpty)
        for (name, set) in sets {
            let isReference = set.colors.allSatisfy { $0.color?.reference != nil }
            let hasDark = set.colors.contains { $0.appearances.isDark }
            #expect(isReference || hasDark, "Interface/\(name) needs a Dark value or a system reference")
        }
    }
}
