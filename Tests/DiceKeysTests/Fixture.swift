//
//  Fixture.swift
//  DiceKeysTests
//

import Foundation

/// Files in `Fixtures/`, checked in once and never regenerated.
enum Fixture {
    private final class FixtureBundle {}

    static func data(_ name: String) throws -> Data {
        let bundle = Bundle(for: FixtureBundle.self)
        guard let url = bundle.url(forResource: name, withExtension: nil) else { throw CocoaError(.fileNoSuchFile) }
        return try Data(contentsOf: url)
    }

    static func text(_ name: String) throws -> String {
        String(decoding: try data(name), as: UTF8.self).trimmingCharacters(in: .newlines)
    }
}
