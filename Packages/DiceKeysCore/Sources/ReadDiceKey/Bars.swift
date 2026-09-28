//
//  Bars.swift
//  ReadDiceKey
//
//  Finding the undoverlines: every rectangle in the frame shaped and sized like one.
//

import Foundation

/// The rectangles in the image that could be undoverlines.
///
/// An undoverline is a dark bar on a light die. However the light falls across the key,
/// some brightness separates each bar from its own die, so the image is thresholded at
/// twelve levels and every border traced at each. A border whose smallest enclosing
/// rectangle has an undoverline's proportions (0.177 as thick as it is long, with 50%
/// slack) is a candidate. All 50 undoverlines of a key are nearly the same size, so when
/// there are more than 25 candidates only those within 25% of the most common area are
/// kept, and of a bar found at several thresholds, the one closest to that area.
func findBars(in image: GrayImage) -> [Bar] {
    guard let brightest = image.pixels.max() else { return [] }
    let thresholds = (2...13).map { UInt8($0 * 255 / 13) }.filter { $0 <= brightest }
    guard !thresholds.isEmpty else { return [] }

    // The levels are independent. Each worker takes every `workers`-th level and reuses one
    // label plane for all of them; the results are joined in threshold order.
    let workers = min(thresholds.count, ProcessInfo.processInfo.activeProcessorCount)
    let perLevel = UnsafeMutableBufferPointer<[Bar]>.allocate(capacity: thresholds.count)
    perLevel.initialize(repeating: [])
    defer {
        perLevel.deinitialize()
        perLevel.deallocate()
    }
    nonisolated(unsafe) let results = perLevel
    DispatchQueue.concurrentPerform(iterations: workers) { worker in
        var scratch = ContourScratch()
        for level in stride(from: worker, to: thresholds.count, by: workers) {
            results[level] = findContours(in: image, atLeast: thresholds[level], minPerimeter: 50, scratch: &scratch)
                .map(minAreaRect)
                .filter(isShapedLikeUndoverline)
        }
    }
    var bars = Array(perLevel.joined())
    guard bars.count > 25 else { return bars }

    let area = modalArea(of: bars)
    bars = bars.filter { $0.area >= 0.75 * area && $0.area <= area / 0.75 }
    var distinct: [Bar] = []
    for bar in bars {
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
    guard bar.length > 0 else { return false }
    let thickness = bar.width / bar.length
    return thickness >= FaceDimensions.undoverlineThickness / 1.5 && thickness <= FaceDimensions.undoverlineThickness * 1.5
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
