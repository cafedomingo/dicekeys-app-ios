//
//  AssetCatalogSource.swift
//  DiceKeysTests
//
//  The asset catalogs as source. The compiled catalog does not record which appearances an
//  entry declared or which files it was drawn from, so tests about those read the
//  `Contents.json` files in the repository.
//

import Foundation

enum AssetCatalogSource {
    static let resources = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appending(path: "DiceKeys/Resources")

    /// Every entry of one kind (`.colorset`, `.imageset`) in a catalog folder, by name, with its
    /// `Contents.json` decoded.
    static func entries<Contents: Decodable>(
        _ type: Contents.Type, in folder: String, suffix: String
    ) throws -> [(name: String, contents: Contents)] {
        let url = resources.appending(path: folder)
        return try FileManager.default.contentsOfDirectory(atPath: url.path(percentEncoded: false))
            .filter { $0.hasSuffix(suffix) }
            .sorted()
            .map { entry in
                let data = try Data(contentsOf: url.appending(path: "\(entry)/Contents.json"))
                return (String(entry.dropLast(suffix.count)), try JSONDecoder().decode(type, from: data))
            }
    }
}

/// An entry's `appearances`, of which only the luminosity value matters here.
struct CatalogAppearance: Decodable {
    let value: String
}

extension [CatalogAppearance]? {
    var isDark: Bool { self?.contains { $0.value == "dark" } == true }
}
