//
//  RegionTests.swift
//  ReadDiceKeyTests
//

import Testing
@testable import ReadDiceKey

@Suite("darkRegions")
struct RegionTests {
    /// A white image with the listed pixels black.
    private func image(width: Int, height: Int, dark: [(Int, Int)]) -> GrayImage {
        var pixels = [UInt8](repeating: 255, count: width * height)
        for (x, y) in dark { pixels[y * width + x] = 0 }
        return GrayImage(width: width, height: height, pixels: pixels)
    }

    @Test("joins dark pixels that share an edge, not those that only touch at a corner")
    func joinsAlongEdges() {
        // An L of three pixels, and a pixel touching its corner diagonally.
        let dark = [(1, 1), (1, 2), (2, 2), (3, 3)]
        #expect(darkRegions(in: image(width: 6, height: 6, dark: dark), darkerThan: 128, minPixels: 1).count == 2)
    }

    @Test("joins runs that meet only further along the row")
    func joinsThroughALaterRow() {
        // A U: two columns joined by the bottom row, so they are one region.
        let dark = [(1, 1), (4, 1), (1, 2), (4, 2), (1, 3), (2, 3), (3, 3), (4, 3)]
        #expect(darkRegions(in: image(width: 6, height: 6, dark: dark), darkerThan: 128, minPixels: 1).count == 1)
    }

    @Test("leaves out regions smaller than the minimum")
    func dropsSmallRegions() {
        let dark = [(1, 1), (1, 2), (2, 2), (4, 4)]
        #expect(darkRegions(in: image(width: 6, height: 6, dark: dark), darkerThan: 128, minPixels: 2).count == 1)
    }

    @Test("fits a region with the rectangle its pixels cover")
    func fitsThePixelsOutline() throws {
        let dark = (2..<22).flatMap { x in (3..<7).map { y in (x, y) } }
        let regions = darkRegions(in: image(width: 30, height: 10, dark: dark), darkerThan: 128, minPixels: 1)
        let bar = try #require(regions.first.flatMap(smallestRectangle(around:)))
        #expect(regions.count == 1)
        #expect(bar.length == 20 && bar.width == 4)
        #expect(bar.center == Point(12, 5))
    }
}
