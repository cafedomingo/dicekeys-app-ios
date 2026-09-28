//
//  ScannerCorpusTests.swift
//  ReadDiceKeyTests
//
//  Runs the scanner over the photo corpus (upstream dicekeys/read-dicekey's photos and the
//  owner's). Each file is named after the DiceKey it shows (75 characters: letter, digit
//  and orientation per face, the orientation as t/r/b/l or as 0-3 clockwise turns, and
//  "---" for a die that cannot be seen), optionally followed by a "-note" or "_note"
//  suffix; files named "nokey-..." show no DiceKey. Each photo is one frame, so this is
//  stricter than the app, which merges faces across frames.
//

import AVFoundation
import CoreGraphics
import Foundation
import ImageIO
import Testing
@testable import ReadDiceKey

// MARK: - Corpus

struct CorpusImage: Sendable, CustomTestStringConvertible {
    let url: URL
    /// The faces the file name gives (nil for a die that cannot be seen), or nil when it names none.
    let expected: [ScannedFace?]?
    /// False for the photos taken outside what the scanning overlay asks for, which are only
    /// required not to be misread.
    let mustRead: Bool
    /// True for photos with no DiceKey in them, which must read nothing.
    let showsNoKey: Bool

    var testDescription: String { url.lastPathComponent }

    static let crashOnlyPrefixes = ["CausedCrash", "G21J20C42", "U5bC4bE1l", "Y6bS2rG4b"]
    static let crashOnlySuffixes = ["-super-low-res", "-dark-tilted", "-top-row-cut", "-far-glare", "-tilted-lit", "-tilted-dim", "-blurry"]

    static let all: [CorpusImage] = {
        let dir = Bundle.module.resourceURL!.appendingPathComponent("Fixtures/images")
        let files = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
        return files
            .filter { ["jpg", "png"].contains($0.pathExtension.lowercased()) }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
            .map { url in
                let base = url.deletingPathExtension().lastPathComponent
                let showsNoKey = base.hasPrefix("nokey")
                let crashOnly = showsNoKey || crashOnlyPrefixes.contains { base.hasPrefix($0) }
                    || crashOnlySuffixes.contains { base.dropFirst(75) == $0 }
                return CorpusImage(url: url, expected: Corpus.faces(of: String(base.prefix(75))), mustRead: !crashOnly, showsNoKey: showsNoKey)
            }
    }()
}

enum Corpus {
    enum Size: String, CaseIterable, Sendable {
        case native
        /// The whole photo at the app's scale: its shorter side 1080 pixels, the side of the
        /// app's frames. The photos were not taken through the scanning overlay, so cropping
        /// them to its square can cut off dice that a user would have brought into it.
        case shorterSide1080
        /// Exactly what the app scans: the centered 1080-pixel square.
        case centeredSquare1080
    }

    /// The photo as gray pixels, EXIF orientation applied.
    static func gray(from url: URL, size: Size) throws -> GrayImage {
        if size == .centeredSquare1080 {
            return try gray(from: url, square: 1080)
        }
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
        let scale = size == .native ? 1 : 1080 / Double(min(image.width, image.height))
        return try draw(image, width: Int((Double(image.width) * scale).rounded()), height: Int((Double(image.height) * scale).rounded()))
    }

    /// The photo scaled to cover a `side` x `side` square and cropped to its center, as the app frames the camera.
    static func gray(from url: URL, square side: Int) throws -> GrayImage {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                  kCGImageSourceCreateThumbnailWithTransform: true,
                  kCGImageSourceCreateThumbnailFromImageAlways: true,
                  kCGImageSourceThumbnailMaxPixelSize: side * 2
              ] as CFDictionary) else {
            throw CorpusError.cannotDecode(url.lastPathComponent)
        }
        let scale = Double(side) / Double(min(image.width, image.height))
        let drawn = CGSize(width: Double(image.width) * scale, height: Double(image.height) * scale)
        return try draw(image, width: side, height: side, in: CGRect(
            origin: CGPoint(x: (Double(side) - drawn.width) / 2, y: (Double(side) - drawn.height) / 2), size: drawn
        ))
    }

    private static func draw(_ image: CGImage, width: Int, height: Int, in rect: CGRect? = nil) throws -> GrayImage {
        guard let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width,
            space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue
        ), let data = context.data else {
            throw CorpusError.cannotDecode("\(width)x\(height)")
        }
        context.interpolationQuality = .high
        context.draw(image, in: rect ?? CGRect(x: 0, y: 0, width: width, height: height))
        let pixels = Array(UnsafeBufferPointer(start: data.assumingMemoryBound(to: UInt8.self), count: width * height))
        return GrayImage(width: width, height: height, pixels: pixels)
    }

    /// Splits a 75-character name into faces, nil for "---"; nil if it is not a key's name.
    static func faces(of name: String) -> [ScannedFace?]? {
        let chars = Array(name)
        guard chars.count == 75 else { return nil }
        let turnsByOrientation: [Character: Int] = ["t": 0, "r": 1, "b": 2, "l": 3, "0": 0, "1": 1, "2": 2, "3": 3]
        var faces: [ScannedFace?] = []
        for i in 0..<25 {
            if chars[i * 3...i * 3 + 2] == ["-", "-", "-"] {
                faces.append(nil)
                continue
            }
            guard let turns = turnsByOrientation[chars[i * 3 + 2]] else { return nil }
            faces.append(ScannedFace(letter: chars[i * 3], digit: chars[i * 3 + 1], clockwiseTurns: turns))
        }
        return faces
    }

    /// The key as it reads after turning the box a quarter turn clockwise.
    static func turnedClockwise(_ faces: [ScannedFace?]) -> [ScannedFace?] {
        var turned = faces
        for row in 0..<5 {
            for column in 0..<5 {
                turned[column * 5 + (4 - row)] = faces[row * 5 + column].map {
                    ScannedFace(letter: $0.letter, digit: $0.digit, clockwiseTurns: ($0.clockwiseTurns + 1) % 4)
                }
            }
        }
        return turned
    }

    /// Faces read right and read wrong, in whichever of the key's four rotations reads best.
    /// A face read where the expectation cannot see a die counts as neither.
    static func score(_ read: [ScannedFace?], against expected: [ScannedFace?]) -> (right: Int, wrong: Int) {
        var candidate = expected
        var best = (right: -1, wrong: 0)
        for _ in 0..<4 {
            var right = 0, wrong = 0
            for (face, want) in zip(read, candidate) {
                guard let face, let want else { continue }
                if face == want { right += 1 } else { wrong += 1 }
            }
            if right > best.right { best = (right, wrong) }
            candidate = turnedClockwise(candidate)
        }
        return best
    }

    enum CorpusError: Error { case cannotDecode(String) }
}

// MARK: - Tests

@Suite("Scanner photo corpus")
struct ScannerCorpusTests {
    /// The fewest faces the photos that must read may yield between them, one frame each at the
    /// app's frame size. It sits a little below what they read (the test prints that), so that
    /// another Mac's JPEG decoder, which can move a face or two, cannot fail it.
    static let minimumFacesRead = 530

    static let cases = CorpusImage.all.flatMap { image in Corpus.Size.allCases.map { (image, $0) } }

    @Test("corpus is present")
    func corpusPresent() {
        #expect(CorpusImage.all.count >= 20)
    }

    @Test("never reads a face wrong", arguments: cases)
    func neverMisreads(image: CorpusImage, size: Corpus.Size) throws {
        var scanner = DiceKeyScanner()
        scanner.scan(try Corpus.gray(from: image.url, size: size))
        guard let expected = image.expected else { return }
        #expect(Corpus.score(scanner.faces, against: expected).wrong == 0)
    }

    @Test("reads nothing where there is no key", arguments: cases.filter { $0.0.showsNoKey })
    func readsNothingWithoutAKey(image: CorpusImage, size: Corpus.Size) throws {
        var scanner = DiceKeyScanner()
        #expect(scanner.scan(try Corpus.gray(from: image.url, size: size)).isEmpty)
        #expect(scanner.faces.allSatisfy { $0 == nil })
    }

    @Test("reads nearly every face of a photo that must read, at the app's frame size", arguments: CorpusImage.all.filter(\.mustRead))
    func readsMostFaces(image: CorpusImage) throws {
        var scanner = DiceKeyScanner()
        scanner.scan(try Corpus.gray(from: image.url, size: .shorterSide1080))
        let expected = try #require(image.expected)
        #expect(Corpus.score(scanner.faces, against: expected).right >= 20)
    }

    @Test("reads at least the recorded number of faces, at the app's frame size")
    func readsEnoughFaces() throws {
        var total = 0
        for image in CorpusImage.all where image.mustRead {
            var scanner = DiceKeyScanner()
            scanner.scan(try Corpus.gray(from: image.url, size: .shorterSide1080))
            total += Corpus.score(scanner.faces, against: try #require(image.expected)).right
        }
        print("corpus: \(total) faces read")
        #expect(total >= Self.minimumFacesRead)
    }

    /// Every video, played through one scanner a frame at a time the way the app feeds it:
    /// the centered square of each frame's luma plane.
    static let videos: [URL] = {
        let dir = Bundle.module.resourceURL!.appendingPathComponent("Fixtures/videos")
        return ((try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? [])
            .filter { $0.pathExtension.lowercased() == "mov" }
    }()

    @Test("never reads a face wrong across a video", arguments: videos)
    func neverMisreadsAVideo(url: URL) async throws {
        let asset = AVURLAsset(url: url)
        let track = try #require(try await asset.loadTracks(withMediaType: .video).first)
        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarFullRange
        ])
        reader.add(output)
        #expect(reader.startReading())
        var scanner = DiceKeyScanner()
        while let sample = output.copyNextSampleBuffer() {
            guard let frame = sample.imageBuffer, let image = GrayImage(centeredSquareOf: frame) else { continue }
            scanner.scan(image)
            let expected = try #require(Corpus.faces(of: String(url.deletingPathExtension().lastPathComponent.prefix(75))))
            #expect(Corpus.score(scanner.faces, against: expected).wrong == 0)
        }
        print("video \(url.lastPathComponent.suffix(12)): \(scanner.faces.compactMap { $0 }.count) faces known after the last frame")
        #expect(scanner.faces.compactMap { $0 }.count >= 17)
    }
}
