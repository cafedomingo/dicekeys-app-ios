//
//  ContourMemoryTests.swift
//  ReadDiceKeyTests
//

import Foundation
import Testing
@testable import ReadDiceKey

@Suite("findContours memory")
struct ContourMemoryTests {
    /// One long border (a comb, with a corner at every tooth) above thousands of 2x2 specks.
    private func combAboveSpecks(width: Int, speckRows: Int) -> GrayImage {
        let height = 4 + speckRows * 3
        var pixels = [UInt8](repeating: 0, count: width * height)
        for x in 0..<width {
            pixels[x] = 255
            if x % 2 == 0 {
                pixels[width + x] = 255
                pixels[2 * width + x] = 255
            }
        }
        for row in 0..<speckRows {
            let y = 4 + row * 3
            for x in stride(from: 0, to: width - 1, by: 3) {
                for (dx, dy) in [(0, 0), (1, 0), (0, 1), (1, 1)] {
                    pixels[(y + dy) * width + x + dx] = 255
                }
            }
        }
        return GrayImage(width: width, height: height, pixels: pixels)
    }

    @Test("each contour keeps only the memory its own points need")
    func contourCapacityTracksItsLength() {
        var scratch = ContourScratch()
        let contours = findContours(in: combAboveSpecks(width: 1000, speckRows: 10), atLeast: 1, minPerimeter: 0, scratch: &scratch)
        let longest = contours.map(\.count).max() ?? 0
        #expect(longest > 500, "the comb should trace as one long border")
        #expect(contours.count > 3000, "every speck should be a contour of its own")

        let points = contours.reduce(0) { $0 + $1.count }
        let capacity = contours.reduce(0) { $0 + $1.capacity }
        #expect(capacity <= 2 * points)
    }

    @Test("a minimum perimeter keeps exactly the borders the filter afterwards would")
    func minimumPerimeterMatchesFilteringAfterwards() throws {
        let photo = try #require(CorpusImage.all.first)
        let gray = try Corpus.gray(from: photo.url, square: 1080)
        for image in [combAboveSpecks(width: 1000, speckRows: 10), gray] {
            for threshold: UInt8 in [1, 98, 156] {
                var scratch = ContourScratch()
                let all = findContours(in: image, atLeast: threshold, minPerimeter: 0, scratch: &scratch)
                let kept = findContours(in: image, atLeast: threshold, minPerimeter: 50, scratch: &scratch)
                #expect(kept == all.filter { arcLengthOpen($0) >= 50 })
                #expect(kept.count < all.count)
            }
        }
    }
}
