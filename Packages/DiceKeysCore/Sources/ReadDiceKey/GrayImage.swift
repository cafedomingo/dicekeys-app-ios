//
//  GrayImage.swift
//  ReadDiceKey
//

import CoreVideo

/// An 8-bit grayscale image, one byte per pixel, rows top to bottom.
public struct GrayImage: Sendable {
    public let width: Int
    public let height: Int
    public let pixels: [UInt8]

    public init(width: Int, height: Int, pixels: [UInt8]) {
        precondition(width >= 0 && height >= 0 && pixels.count == width * height, "pixels must hold width * height bytes")
        self.width = width
        self.height = height
        self.pixels = pixels
    }

    /// The largest centered square of a camera frame's luma (brightness) plane. The camera
    /// delivers bi-planar Y'CbCr, whose first plane already is the grayscale image, so this
    /// is a copy of rows. Nil for frames in any other format.
    public init?(centeredSquareOf frame: CVPixelBuffer) {
        let format = CVPixelBufferGetPixelFormatType(frame)
        guard format == kCVPixelFormatType_420YpCbCr8BiPlanarFullRange
                || format == kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange else { return nil }
        CVPixelBufferLockBaseAddress(frame, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(frame, .readOnly) }
        guard let luma = CVPixelBufferGetBaseAddressOfPlane(frame, 0) else { return nil }
        let frameWidth = CVPixelBufferGetWidthOfPlane(frame, 0)
        let frameHeight = CVPixelBufferGetHeightOfPlane(frame, 0)
        let rowBytes = CVPixelBufferGetBytesPerRowOfPlane(frame, 0)
        let side = min(frameWidth, frameHeight)
        let first = luma + ((frameHeight - side) / 2) * rowBytes + (frameWidth - side) / 2
        let pixels = [UInt8](unsafeUninitializedCapacity: side * side) { buffer, count in
            for row in 0..<side {
                (buffer.baseAddress! + row * side).initialize(from: (first + row * rowBytes).assumingMemoryBound(to: UInt8.self), count: side)
            }
            count = side * side
        }
        self.init(width: side, height: side, pixels: pixels)
    }
}
