//
//  ModalAreaTests.swift
//  ReadDiceKeyTests
//

import Foundation
import Testing
@testable import ReadDiceKey

@Suite("findTighestModalAreaOfRects")
struct ModalAreaTests {
    private func rects(areas: [Float]) -> [RectangleDetected] {
        areas.map { area in
            RectangleDetected(
                rotatedRect: RotatedRect(center: .zero, size: Size2f(area, 1), angle: 0),
                contourArea: area,
                foundAtThreshold: 0
            )
        }
    }

    // The reference C++ stopped the search two centres short, so 26, 28, ... 36 candidates
    // ran no iterations, returned NaN, and the NaN area bounds then discarded every
    // undoverline in the frame.
    @Test("every candidate count above 25 yields an area", arguments: 26...60)
    func findsAreaForEveryCount(count: Int) {
        let areas = (0..<count).map { Float(100 + $0) }
        #expect(!findTighestModalAreaOfRects(rects(areas: areas)).isNaN)
    }

    @Test("the tightest cluster at the top of the sorted areas is found")
    func clusterAtTop() {
        // 10 scattered small areas, then 26 near-identical ones: the search must reach the
        // last centre to find them.
        let scattered = (0..<10).map { Float(10 + $0 * 7) }
        let cluster = (0..<26).map { Float(1000 + $0) }
        let area = findTighestModalAreaOfRects(rects(areas: scattered + cluster))
        #expect(area >= 1000 && area <= 1025)
    }
}
