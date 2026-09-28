//
//  Bars.swift
//  ReadDiceKey
//
//  Finding the undoverlines: every rectangle in the frame shaped and sized like one.
//

import DiceKeySpecification
import Foundation

/// The rectangles in the image that could be undoverlines.
///
/// An undoverline is a dark bar on a light die. However the light falls across the key,
/// some brightness separates each bar from its own die, so the image is thresholded at
/// twelve levels and every border traced at each. A border whose smallest enclosing
/// rectangle has an undoverline's proportions (0.177 as thick as it is long, with 50%
/// slack) is a candidate. All 50 undoverlines of a key are nearly the same size, so only
/// candidates within 25% of the most common area are kept, and of a bar found at several
/// thresholds, the one closest to that area.
func findBars(in image: GrayImage) -> [Bar] {
    guard let brightest = image.pixels.max() else { return [] }
    let thresholds = (2...13).map { UInt8($0 * 255 / 13) }.filter { $0 <= brightest }
    guard !thresholds.isEmpty else { return [] }

    // The levels are independent, so they are traced in parallel and joined in threshold order.
    let perLevel = UnsafeMutableBufferPointer<[Bar]>.allocate(capacity: thresholds.count)
    perLevel.initialize(repeating: [])
    defer {
        perLevel.deinitialize()
        perLevel.deallocate()
    }
    nonisolated(unsafe) let results = perLevel
    DispatchQueue.concurrentPerform(iterations: thresholds.count) { level in
        results[level] = traceBorders(in: image, atLeast: thresholds[level], minPerimeter: 50)
            .compactMap(smallestRectangle(around:))
            .filter(isShapedLikeUndoverline)
    }
    let bars = Array(perLevel.joined())
    let area = modalArea(of: bars)
    var distinct: [Bar] = []
    for bar in bars where bar.area >= 0.75 * area && bar.area <= area / 0.75 {
        if let same = distinct.firstIndex(where: { $0.contains(bar.center) || bar.contains($0.center) }) {
            if abs(bar.area - area) < abs(distinct[same].area - area) {
                distinct[same] = bar
            }
        } else {
            distinct.append(bar)
        }
    }
    return distinct
}

private func isShapedLikeUndoverline(_ bar: Bar) -> Bool {
    let thickness = bar.width / bar.length
    let printed = Float(FaceDimensionsFractional.undoverlineThickness / FaceDimensionsFractional.undoverlineLength)
    return thickness >= printed / 1.5 && thickness <= printed * 1.5
}

/// The area at the middle of the tightest run of 35 consecutive areas (fewer when there are
/// fewer than 36 bars), tightness being the ratio of the run's largest area to its smallest.
/// A tight run of much larger bars (ratio under 1.2, middle over three times the area found
/// so far) also wins, so that a crowd of equal tiny specks cannot outvote the undoverlines.
private func modalArea(of bars: [Bar]) -> Float {
    let areas = bars.map(\.area).sorted()
    let half = max(0, min(areas.count / 2 - 1, 17))
    var tightest = Float.greatestFiniteMagnitude
    var modal = Float.nan
    for i in half..<(areas.count - half) {
        let ratio = areas[i + half] / areas[i - half]
        if ratio < tightest || (ratio < 1.2 && areas[i] > 3 * modal) {
            tightest = ratio
            modal = areas[i]
        }
    }
    return modal
}
