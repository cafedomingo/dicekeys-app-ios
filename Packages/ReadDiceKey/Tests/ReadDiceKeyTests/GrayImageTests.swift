//
//  GrayImageTests.swift
//  ReadDiceKeyTests
//

import CoreVideo
import Testing
@testable import ReadDiceKey

@Suite("GrayImage from a camera frame")
struct GrayImageTests {
    /// A bi-planar Y'CbCr frame whose luma at (x, y) is x + 10 * y.
    private func frame(width: Int, height: Int, format: OSType = kCVPixelFormatType_420YpCbCr8BiPlanarFullRange) throws -> CVPixelBuffer {
        var buffer: CVPixelBuffer?
        CVPixelBufferCreate(kCFAllocatorDefault, width, height, format, nil, &buffer)
        let frame = try #require(buffer)
        CVPixelBufferLockBaseAddress(frame, [])
        defer { CVPixelBufferUnlockBaseAddress(frame, []) }
        if CVPixelBufferIsPlanar(frame) {
            let luma = try #require(CVPixelBufferGetBaseAddressOfPlane(frame, 0)).assumingMemoryBound(to: UInt8.self)
            let rowBytes = CVPixelBufferGetBytesPerRowOfPlane(frame, 0)
            for y in 0..<height {
                for x in 0..<width {
                    luma[y * rowBytes + x] = UInt8(x + 10 * y)
                }
            }
        }
        return frame
    }

    @Test("a landscape frame gives the middle square of its luma, row padding skipped")
    func landscape() throws {
        let camera = try frame(width: 6, height: 4)
        try #require(CVPixelBufferGetBytesPerRowOfPlane(camera, 0) > 6)
        let image = try #require(GrayImage(centeredSquareOf: camera))
        #expect(image.width == 4 && image.height == 4)
        #expect(image.pixels == (0..<4).flatMap { y in (1...4).map { x in UInt8(x + 10 * y) } })
    }

    @Test("a portrait frame gives the middle square too")
    func portrait() throws {
        let image = try #require(GrayImage(centeredSquareOf: try frame(width: 4, height: 6)))
        #expect(image.width == 4 && image.height == 4)
        #expect(image.pixels == (1...4).flatMap { y in (0..<4).map { x in UInt8(x + 10 * y) } })
    }

    @Test("video-range frames are read as well")
    func videoRange() throws {
        let image = try #require(GrayImage(centeredSquareOf: try frame(width: 4, height: 4, format: kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange)))
        #expect(image.pixels[5] == 11)
    }

    @Test("a frame with no luma plane is refused")
    func bgraIsRefused() throws {
        #expect(GrayImage(centeredSquareOf: try frame(width: 4, height: 4, format: kCVPixelFormatType_32BGRA)) == nil)
    }
}
