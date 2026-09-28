//
//  GrayImage.swift
//  ReadDiceKey
//

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
}
