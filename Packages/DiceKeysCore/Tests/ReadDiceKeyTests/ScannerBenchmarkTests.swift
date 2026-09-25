//
//  ScannerBenchmarkTests.swift
//  ReadDiceKeyTests
//
//  Opt-in timing of `DiceKeyScanner.process` on a camera-sized frame. Skipped unless
//  SCANNER_BENCHMARK is set, so CI stays fast; run it with
//
//      SCANNER_BENCHMARK=1 swift test -c release --filter ScannerBenchmark
//
//  The app feeds the scanner the centred square of a 1920x1080 session, so the
//  frame here is a corpus photo scaled to 1080x1080. The first call warms up the
//  allocator; the median of the rest is the number to compare against the notes in
//  docs/SCANNER-PORT-NOTES.md.
//

import CoreGraphics
import Foundation
import ImageIO
import Testing
@testable import ReadDiceKey

@Suite("Scanner benchmark (opt-in)", .enabled(if: ProcessInfo.processInfo.environment["SCANNER_BENCHMARK"] != nil))
struct ScannerBenchmarkTests {
    @Test("time per 1080x1080 frame")
    func framesPerSecond() throws {
        let side = 1080
        let url = try #require(CorpusImage.all.first { $0.url.lastPathComponent.hasPrefix("K13Y63A23") && !$0.url.lastPathComponent.contains("glare") }?.url)
        let (rgba, width, height) = try Corpus.rgba(from: url, scaledToSquare: side)
        #expect(width == side && height == side)

        var samples: [Duration] = []
        for _ in 0..<12 {
            // A fresh scanner each time: the reader stops doing work once it has a complete read.
            let scanner = DiceKeyScanner()
            let clock = ContinuousClock()
            let elapsed = clock.measure { scanner.process(rgba: rgba, width: width, height: height) }
            samples.append(elapsed)
        }
        let sorted = samples.dropFirst().sorted()
        let median = sorted[sorted.count / 2]
        let ms = { (d: Duration) in Double(d.components.seconds) * 1000 + Double(d.components.attoseconds) / 1e15 }
        print("scanner benchmark: \(side)x\(side) frame, median \(String(format: "%.1f", ms(median))) ms, min \(String(format: "%.1f", ms(sorted.first!))) ms, max \(String(format: "%.1f", ms(sorted.last!))) ms")
        #expect(median < .seconds(2))
    }
}

extension Corpus {
    /// `rgba(from:)` with the image scaled (aspect-filled and centre-cropped) to a square of `side` pixels.
    static func rgba(from url: URL, scaledToSquare side: Int) throws -> (data: Data, width: Int, height: Int) {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else {
            throw CorpusError.cannotDecode(url.lastPathComponent)
        }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: side * 2
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            throw CorpusError.cannotDecode(url.lastPathComponent)
        }
        let scale = Double(side) / Double(min(image.width, image.height))
        let drawn = CGSize(width: Double(image.width) * scale, height: Double(image.height) * scale)
        let origin = CGPoint(x: (Double(side) - drawn.width) / 2, y: (Double(side) - drawn.height) / 2)
        var buffer = Data(count: side * side * 4)
        try buffer.withUnsafeMutableBytes { raw in
            guard let context = CGContext(
                data: raw.baseAddress, width: side, height: side, bitsPerComponent: 8, bytesPerRow: side * 4,
                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { throw CorpusError.cannotDecode(url.lastPathComponent) }
            context.interpolationQuality = .high
            context.draw(image, in: CGRect(origin: origin, size: drawn))
        }
        return (buffer, side, side)
    }
}
