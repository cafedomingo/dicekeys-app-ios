//
//  FrameConversionBenchmarkTests.swift
//  DiceKeysTests
//
//  Opt-in timing of the per-frame work that happens before the scanner sees a frame.
//  Run with:  FRAME_BENCHMARK=1 xcodebuild test -only-testing:DiceKeysTests/FrameConversionBenchmarkTests ...
//

import CoreImage
import CoreVideo
import Foundation
import Testing
@testable import DiceKeys

@Suite("Frame conversion benchmark (opt-in)", .enabled(if: ProcessInfo.processInfo.environment["FRAME_BENCHMARK"] != nil))
struct FrameConversionBenchmarkTests {
    /// A 1920x1080 BGRA buffer, the shape a 1080p capture session delivers.
    static func makeBuffer(width: Int = 1920, height: Int = 1080) -> CVPixelBuffer {
        var buffer: CVPixelBuffer?
        CVPixelBufferCreate(kCFAllocatorDefault, width, height, kCVPixelFormatType_32BGRA,
                            [kCVPixelBufferIOSurfacePropertiesKey: [:] as CFDictionary] as CFDictionary, &buffer)
        let pixels = buffer!
        CVPixelBufferLockBaseAddress(pixels, [])
        if let base = CVPixelBufferGetBaseAddress(pixels) {
            let rowBytes = CVPixelBufferGetBytesPerRow(pixels)
            let bytes = base.assumingMemoryBound(to: UInt8.self)
            for y in 0..<height {
                for x in 0..<(rowBytes / 4) {
                    let i = y * rowBytes + x * 4
                    let v = UInt8truncating(x &* 7 &+ y &* 3)
                    bytes[i] = v; bytes[i + 1] = v &+ 40; bytes[i + 2] = v &+ 80; bytes[i + 3] = 255
                }
            }
        }
        CVPixelBufferUnlockBaseAddress(pixels, [])
        return pixels
    }

    static func UInt8truncating(_ v: Int) -> UInt8 { UInt8(truncatingIfNeeded: v) }

    func ms(_ block: () -> Void) -> Double {
        let d = ContinuousClock().measure(block)
        return Double(d.components.seconds) * 1000 + Double(d.components.attoseconds) / 1e15
    }

    @Test("time to crop and convert one camera frame")
    func conversionCost() throws {
        let pixels = Self.makeBuffer()
        let context = CIContext(options: nil)
        // Warm up: the first call builds CoreImage's pipeline.
        for _ in 0..<3 { _ = rgbaCenteredSquare(from: pixels, orientation: .up, context: context) }

        var samples: [Double] = []
        for _ in 0..<15 {
            samples.append(ms { _ = rgbaCenteredSquare(from: pixels, orientation: .up, context: context) })
        }
        let sorted = samples.sorted()
        let median = sorted[sorted.count / 2]

        // The same crop rendered straight into a byte buffer, skipping the intermediate CGImage.
        let side = 1080
        var direct = Data(count: side * side * 4)
        let square = CGRect(x: (1920 - side) / 2, y: 0, width: side, height: side)
        let ciImage = CIImage(cvPixelBuffer: pixels)
        let format = CIFormat.RGBA8
        let space = CGColorSpaceCreateDeviceRGB()
        var directSamples: [Double] = []
        for _ in 0..<15 {
            directSamples.append(ms {
                direct.withUnsafeMutableBytes { raw in
                    context.render(ciImage, toBitmap: raw.baseAddress!, rowBytes: side * 4,
                                   bounds: square, format: format, colorSpace: space)
                }
            })
        }
        let directMedian = directSamples.sorted()[directSamples.count / 2]

        let line = String(format: "FRAME median %.2f ms (current: oriented + createCGImage + redraw), %.2f ms (render straight to bitmap)", median, directMedian)
        print(line)
        // xcodebuild swallows test stdout; a file survives.
        try? line.write(toFile: "/tmp/frame-benchmark.txt", atomically: true, encoding: .utf8)
        #expect(median < 100)
    }
}
