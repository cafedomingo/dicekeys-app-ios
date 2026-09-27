//
//  ContourMemoryTests.swift
//  ReadDiceKeyTests
//

import Foundation
import Testing
@testable import ReadDiceKey

@Suite("findContours memory")
struct ContourMemoryTests {
    /// A comb (one border with a corner at every tooth) across the top, then a grid of
    /// 2x2 specks below it: the shape of a busy camera frame, where one long border is
    /// followed by thousands of small ones.
    private func combAboveSpecks(width: Int, speckRows: Int) -> GrayImage {
        let height = 4 + speckRows * 3
        var image = GrayImage(width: width, height: height)
        for x in 0..<width {
            image.pixels[x] = 255
            if x % 2 == 0 {
                image.pixels[width + x] = 255
                image.pixels[2 * width + x] = 255
            }
        }
        for row in 0..<speckRows {
            let y = 4 + row * 3
            for x in stride(from: 0, to: width - 1, by: 3) {
                for (dx, dy) in [(0, 0), (1, 0), (0, 1), (1, 1)] {
                    image.pixels[(y + dy) * width + x + dx] = 255
                }
            }
        }
        return image
    }

    // A camera frame of the world crashed the app with an allocation failure: every
    // contour traced after a long one was stored with the long one's capacity, so a
    // frame's contours needed (number of contours) x (longest contour) points of memory.
    @Test("each contour keeps only the memory its own points need")
    func contourCapacityTracksItsLength() {
        let contours = findContours(in: combAboveSpecks(width: 1000, speckRows: 10))
        let longest = contours.map(\.count).max() ?? 0
        #expect(longest > 500, "the comb should trace as one long border")
        #expect(contours.count > 3000, "every speck should be a contour of its own")

        let points = contours.reduce(0) { $0 + $1.count }
        let capacity = contours.reduce(0) { $0 + $1.capacity }
        #expect(capacity <= 2 * points)
    }
}
