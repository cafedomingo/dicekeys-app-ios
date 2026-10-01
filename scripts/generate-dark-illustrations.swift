#!/usr/bin/env swift  // Writes the Dark variant of the illustrations that draw black strokes straight onto the
// background, such as the dotted guide lines in the scanning drawings. Those strokes vanish on
// a dark background, so the variant redraws them in light gray and changes nothing else. Line
// art drawn as filled shapes is left alone: it sits on the drawing's own white and lavender
// fills, and is crisper in black. IllustrationCatalogTests checks which drawings need one.
// The output is committed; rerun after editing an illustration.
//
// Usage: swift scripts/generate-dark-illustrations.swift

import Foundation

let catalog = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent()
    .appending(path: "DiceKeys/Resources/Assets.xcassets")

let illustrations = ["Scanning a DiceKey", "Scanning a Stickey"]

/// The light gray the strokes are redrawn in: #A1A1A6 is 8.2:1 on black and 6.6:1 on the
/// system's dark gray.
let lineArt = "#A1A1A6"

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

/// Only elements with no fill of their own are drawn straight onto the background; a stroke
/// around a filled shape sits on that fill and keeps its black. IllustrationCatalogTests
/// draws the same line.
func darkened(_ svg: String) -> String {
    svg.replacing(#/<(?:path|line|polyline|rect|circle|ellipse)\b[^>]*>/#) { element in
        let tag = String(element.0)
        let fill = tag.firstMatch(of: #/\bfill="([^"]+)"/#).map { String($0.1) }
        guard fill == nil || fill == "none" else { return tag }
        return tag.replacing(#/\bstroke="([^"]+)"/#) { match in
            let value = String(match.1)
            return isNearBlack(value) ? "stroke=\"\(lineArt)\"" : String(match.0)
        }
    }
}

for name in illustrations {
    let folder = catalog.appending(path: "\(name).imageset")
    let contentsURL = folder.appending(path: "Contents.json")
    var contents = try JSONSerialization.jsonObject(with: Data(contentsOf: contentsURL)) as! [String: Any]
    var images = (contents["images"] as! [[String: Any]]).filter { $0["appearances"] == nil }
    let lightFile = images[0]["filename"] as! String
    let darkFile = "\(name) Dark.svg"
    let svg = try String(contentsOf: folder.appending(path: lightFile), encoding: .utf8)
    try darkened(svg).write(to: folder.appending(path: darkFile), atomically: true, encoding: .utf8)
    images.append([
        "appearances": [["appearance": "luminosity", "value": "dark"]],
        "filename": darkFile,
        "idiom": "universal"
    ])
    contents["images"] = images
    var properties = contents["properties"] as? [String: Any] ?? [:]
    properties["preserves-vector-representation"] = true
    contents["properties"] = properties
    let data = try JSONSerialization.data(withJSONObject: contents, options: [.prettyPrinted, .sortedKeys])
    try (String(decoding: data, as: UTF8.self) + "\n").write(to: contentsURL, atomically: true, encoding: .utf8)
    print("wrote \(darkFile)")
}
