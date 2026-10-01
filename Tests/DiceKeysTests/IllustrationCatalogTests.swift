//
//  IllustrationCatalogTests.swift
//  DiceKeysTests
//
//  Every picture is vector art drawn at many sizes, so each keeps its vector data. Black line
//  art drawn as filled shapes sits on the drawing's own white and lavender fills and reads in
//  either appearance. A black stroke drawn straight onto the background, such as a dotted
//  guide line, vanishes in dark mode, so exactly the drawings with such strokes carry a Dark
//  variant, and that variant changes those strokes and nothing else.
//

import Foundation
import Testing

/// The parts of an image set's `Contents.json` these rules are about.
private struct ImageSet: Decodable {
    let images: [ImageSetImage]
    let properties: ImageSetProperties?
}

private struct ImageSetImage: Decodable {
    let filename: String?
    let appearances: [CatalogAppearance]?
}

private struct ImageSetProperties: Decodable {
    let preservesVector: Bool?
    let renderingIntent: String?

    enum CodingKeys: String, CodingKey {
        case preservesVector = "preserves-vector-representation"
        case renderingIntent = "template-rendering-intent"
    }
}

struct IllustrationCatalogTests {
    private static func imageSets() throws -> [(name: String, set: ImageSet)] {
        try AssetCatalogSource.entries(ImageSet.self, in: "Assets.xcassets", suffix: ".imageset")
            .map { ($0.name, $0.contents) }
    }

    @Test("every illustration is SVG with its vector data kept")
    func vectorsKept() throws {
        let sets = try Self.imageSets()
        #expect(!sets.isEmpty)
        for (name, set) in sets {
            #expect(set.properties?.preservesVector == true, "\(name) must preserve vector data")
            for file in set.images.compactMap(\.filename) {
                #expect(file.hasSuffix(".svg"), "\(name): \(file) is not SVG")
            }
        }
    }

    /// Drawn over the white sticker sheet, where its black outline is what separates it.
    private static let drawnOnPaper: Set<String> = ["Hand with Sticker"]

    private static func svg(_ set: String, _ file: String) throws -> String {
        try String(
            contentsOf: AssetCatalogSource.resources.appending(path: "Assets.xcassets/\(set).imageset/\(file)"),
            encoding: .utf8)
    }

    // The SVGs total over a megabyte; NSRegularExpression scans them in milliseconds, where
    // Swift Regex takes most of a second.
    // swiftlint:disable force_try
    private static let element = try! NSRegularExpression(
        pattern: #"<(?:path|line|polyline|rect|circle|ellipse)\b([^>]*)>"#)
    private static let fill = try! NSRegularExpression(pattern: #"\bfill="([^"]+)""#)
    private static let stroke = try! NSRegularExpression(pattern: #"\bstroke="([^"]+)""#)
    // swiftlint:enable force_try

    private static func captures(_ pattern: NSRegularExpression, in text: String) -> [String] {
        let string = text as NSString
        return pattern.matches(in: text, range: NSRange(location: 0, length: string.length))
            .map { string.substring(with: $0.range(at: 1)) }
    }

    /// Elements with a near-black stroke and no fill: lines drawn straight onto the background.
    private static func backgroundStrokes(in svg: String) -> Int {
        captures(element, in: svg).filter { attributes in
            let fillValue = captures(fill, in: attributes).first
            return captures(stroke, in: attributes).first.map(isNearBlack) == true
                && (fillValue == nil || fillValue == "none")
        }.count
    }

    private static func fills(in svg: String) -> [String] {
        captures(fill, in: svg)
    }

    @Test("exactly the drawings with strokes on the background have a Dark variant")
    func darkVariantsWhereNeeded() throws {
        for (name, set) in try Self.imageSets() where set.properties?.renderingIntent != "template" {
            let light = try #require(set.images.first { $0.appearances == nil }?.filename)
            let dark = set.images.first { $0.appearances.isDark }?.filename
            let lightSVG = try Self.svg(name, light)
            let needsDark = Self.backgroundStrokes(in: lightSVG) > 0 && !Self.drawnOnPaper.contains(name)
            #expect((dark != nil) == needsDark, "\(name): Dark variant \(needsDark ? "missing" : "not needed")")
            if let dark {
                let darkSVG = try Self.svg(name, dark)
                #expect(Self.backgroundStrokes(in: darkSVG) == 0, "\(name): Dark variant still has black strokes")
                #expect(Self.fills(in: darkSVG) == Self.fills(in: lightSVG), "\(name): Dark variant changed fills")
            }
        }
    }
}

/// Near-black as the dark variants treat it: every channel at most 0x40, and close to gray.
/// The generator and IllustrationCatalogTests carry the same text of this function.
func isNearBlack(_ value: String) -> Bool {
    if value == "black" { return true }
    var hex = value.hasPrefix("#") ? String(value.dropFirst()) : value
    if hex.count == 3 { hex = hex.map { "\($0)\($0)" }.joined() }
    guard hex.count == 6, let rgb = Int(hex, radix: 16) else { return false }
    let channels = [(rgb >> 16) & 0xFF, (rgb >> 8) & 0xFF, rgb & 0xFF]
    return channels.max()! <= 0x40 && channels.max()! - channels.min()! <= 0x10
}
