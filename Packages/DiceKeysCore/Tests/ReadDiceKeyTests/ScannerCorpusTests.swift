//
//  ScannerCorpusTests.swift
//  ReadDiceKeyTests
//
//  Runs the scanner over the photo corpus from upstream dicekeys/read-dicekey. Each
//  file is named after the DiceKey it shows (75 characters with orientations, or 50
//  as 0-3 clockwise turns), optionally followed by a "-note" or "_note" suffix. The
//  per-image tolerances mirror upstream's own test file. This is the acceptance test for
//  any scanner implementation, including the Swift/Vision port: the faces it reads must
//  match the file name in some rotation.
//

import CoreGraphics
import Foundation
import ImageIO
import Testing
@testable import ReadDiceKey

// MARK: - Corpus

struct CorpusImage: Sendable, CustomTestStringConvertible {
    let url: URL
    /// Expected faces as (letter, digit, orientation as t/r/b/l); nil when upstream only
    /// requires the image not to crash the scanner.
    let expected: [(Character, Character, Character)]?
    /// Faces allowed to disagree with the expectation. Mirrors the `maxErrorAllowed`
    /// upstream passes for the same photo (their tests tolerate a few bit errors between
    /// the undoverline codes and the OCR on these).
    let allowedFaceErrors: Int

    var testDescription: String { url.lastPathComponent }

    /// Photos upstream lists with validation disabled or under "tests we hope to pass".
    static let crashOnlyPrefixes = ["CausedCrash", "G21J20C42", "U5bC4bE1l", "Y6bS2rG4b"]
    static let crashOnlySuffixes = ["-super-low-res"]
    static let allowedErrorsByPrefix: [String: Int] = [
        "A32W41T31": 1, "D2tS2tP2l": 1, "E12U31P11": 1, "R60D50Y32": 4
    ]
    static let allowedErrorsBySuffix: [String: Int] = ["-faded": 1]

    static let all: [CorpusImage] = {
        let dir = Bundle.module.resourceURL!.appendingPathComponent("Fixtures/images")
        let files = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
        return files
            .filter { ["jpg", "png"].contains($0.pathExtension.lowercased()) }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
            .map { url in
                let base = url.deletingPathExtension().lastPathComponent
                let stem = String(base.prefix(75))
                let suffix = String(base.dropFirst(75))
                let crashOnly = crashOnlyPrefixes.contains { base.hasPrefix($0) } || crashOnlySuffixes.contains { suffix == $0 }
                let expected = crashOnly ? nil : Corpus.faces(of: stem)
                let allowed = allowedErrorsByPrefix.first { base.hasPrefix($0.key) }?.value
                    ?? allowedErrorsBySuffix[suffix] ?? 0
                return CorpusImage(url: url, expected: expected, allowedFaceErrors: allowed)
            }
    }()
}

// MARK: - Scanner JSON

struct ScannedFace: Decodable {
    struct Point: Decodable { let x: Double; let y: Double }
    struct Line: Decodable { let start: Point; let end: Point }
    struct Undoverline: Decodable { let line: Line; let code: UInt8 }
    let underline: Undoverline?
    let overline: Undoverline?
    let center: Point
    var orientationAsLowercaseLetterTrbl: String?
    let ocrLetterCharsFromMostToLeastLikely: String
    let ocrDigitCharsFromMostToLeastLikely: String

    var letter: Character? { ocrLetterCharsFromMostToLeastLikely.first }
    var digit: Character? { ocrDigitCharsFromMostToLeastLikely.first }
    var orientation: Character? { orientationAsLowercaseLetterTrbl?.first }
}

// MARK: - Helpers

enum Corpus {
    /// Loads an image as tightly packed RGBA8 (premultiplied last), the layout the app's camera path produces.
    /// The EXIF orientation is applied, as OpenCV's `imread` does for the reference output.
    static func rgba(from url: URL) throws -> (data: Data, width: Int, height: Int) {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let raw = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            throw CorpusError.cannotDecode(url.lastPathComponent)
        }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: max(raw.width, raw.height)
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            throw CorpusError.cannotDecode(url.lastPathComponent)
        }
        let width = image.width, height = image.height
        var buffer = Data(count: width * height * 4)
        try buffer.withUnsafeMutableBytes { raw in
            guard let context = CGContext(
                data: raw.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { throw CorpusError.cannotDecode(url.lastPathComponent) }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        }
        return (buffer, width, height)
    }

    static let rotationIndexes = [20, 15, 10, 5, 0, 21, 16, 11, 6, 1, 22, 17, 12, 7, 2, 23, 18, 13, 8, 3, 24, 19, 14, 9, 4]

    static func rotateOrientation(_ o: Character) -> Character {
        switch o {
        case "t": "r"
        case "r": "b"
        case "b": "l"
        case "l": "t"
        default: o
        }
    }

    /// Upstream names faces as letter, digit, orientation; the orientation is either
    /// t/r/b/l or the number of clockwise turns from upright, 0-3.
    static func orientationLetter(_ c: Character) -> Character {
        switch c {
        case "0": "t"
        case "1": "r"
        case "2": "b"
        case "3": "l"
        default: c
        }
    }

    /// Splits a 75-character name into (letter, digit, orientation letter) per face; nil if malformed.
    static func faces(of name: String) -> [(Character, Character, Character)]? {
        let chars = Array(name)
        guard chars.count == 75 else { return nil }
        return (0..<25).map { i in (chars[i * 3], chars[i * 3 + 1], orientationLetter(chars[i * 3 + 2])) }
    }

    static func rotated(_ faces: [(Character, Character, Character)]) -> [(Character, Character, Character)] {
        rotationIndexes.map { i in (faces[i].0, faces[i].1, rotateOrientation(faces[i].2)) }
    }

    /// The smallest number of mismatching faces across the four rotations of the expectation.
    /// Compares the OCR's most likely letter and digit, which is what the reconciled
    /// reading resolves to whenever the undoverline codes and OCR agree.
    static func faceErrors(read: [ScannedFace], expected: [(Character, Character, Character)]) -> Int {
        var candidate = expected
        var best = Int.max
        for _ in 0..<4 {
            var errors = 0
            for (face, want) in zip(read, candidate) where face.letter != want.0 || face.digit != want.1 || face.orientation != want.2 {
                errors += 1
            }
            best = min(best, errors)
            candidate = rotated(candidate)
        }
        return best
    }

    enum CorpusError: Error { case cannotDecode(String) }
}

// MARK: - Tests

@Suite("Scanner photo corpus (from upstream read-dicekey)")
struct ScannerCorpusTests {
    @Test("corpus is present")
    func corpusPresent() {
        #expect(CorpusImage.all.count >= 20)
    }

    @Test("reads the DiceKey in each photo", arguments: CorpusImage.all)
    func readsPhoto(image: CorpusImage) throws {
        let (rgba, width, height) = try Corpus.rgba(from: image.url)
        let scanner = DiceKeyScanner()
        scanner.process(rgba: rgba, width: width, height: height)
        let json = scanner.readResultJSON
        guard let expected = image.expected else {
            // Crash-regression / not-yet-readable image: reaching here without a crash is the test.
            #expect(!json.isEmpty)
            return
        }
        let faces = try JSONDecoder().decode([ScannedFace].self, from: Data(json.utf8))
        #expect(faces.count == 25, "expected 25 faces, got \(faces.count)")
        let errors = Corpus.faceErrors(read: faces, expected: expected)
        #expect(errors <= image.allowedFaceErrors, "\(errors) faces differ from \(image.url.lastPathComponent)")
    }
}
