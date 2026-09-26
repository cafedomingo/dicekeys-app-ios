//
//  FindUndoverlines.swift
//  ReadDiceKey
//
//  Candidate underlines and overlines: graphics/find-rectangles.cpp (contours at 13
//  binarisations of the frame, each turned into a rotated rectangle), graphics/rectangle.h
//  (RectangleDetected) and find-undoverlines.cpp (shape, area and angle filters, then
//  reading each surviving rectangle as an undoverline).
//

import Foundation

// MARK: - rectangle.h RectangleDetected

/// Summary of a contour as a rotated rectangle, for shape tests and a fast overlap test.
struct RectangleDetected: Sendable {
    let contourArea: Float
    let area: Float
    let angleInDegrees: Float
    let longerSideLength: Float
    let shorterSideLength: Float
    let foundAtThreshold: Int
    let rotatedRect: RotatedRect
    let center: Point2f
    let size: Size2f
    let points: [Point2f]

    init(rotatedRect rrect: RotatedRect, contourArea: Float, foundAtThreshold: Int) {
        rotatedRect = rrect
        points = rrect.points()
        self.contourArea = contourArea
        self.foundAtThreshold = foundAtThreshold
        center = rrect.center
        size = rrect.size
        angleInDegrees = rrect.angle
        shorterSideLength = min(rrect.size.width, rrect.size.height)
        longerSideLength = max(rrect.size.width, rrect.size.height)
        area = shorterSideLength * longerSideLength
    }

    init(contour: Contour, foundAtThreshold: Int) {
        self.init(rotatedRect: minAreaRect(contour), contourArea: Float(ReadDiceKey.contourArea(contour)), foundAtThreshold: foundAtThreshold)
    }

    /// Whether the rectangle contains the point (edges count as inside).
    func contains(_ point: Point2f) -> Bool {
        pointPolygonTest(points, point) >= 0
    }

    /// A cheap overlap test with no false positives: one centre lies inside the other rectangle.
    func overlaps(_ other: RectangleDetected) -> Bool {
        other.contains(center) || contains(other.center)
    }
}

// MARK: - find-rectangles.cpp

/// `removeOverlappingRectangles`: keeps, of each set of overlapping rectangles, the one the
/// comparator scores lowest (first one found wins ties).
func removeOverlappingRectangles(_ rectangles: [RectangleDetected], comparatorLowerIsBetter: (RectangleDetected) -> Float) -> [RectangleDetected] {
    var nonOverlapping: [RectangleDetected] = []
    for rect in rectangles {
        var overlapsWithIndex = -1
        for i in 0..<nonOverlapping.count where rect.overlaps(nonOverlapping[i]) {
            overlapsWithIndex = i
            break
        }
        if overlapsWithIndex == -1 {
            nonOverlapping.append(rect)
        } else if comparatorLowerIsBetter(rect) < comparatorLowerIsBetter(nonOverlapping[overlapsWithIndex]) {
            nonOverlapping[overlapsWithIndex] = rect
        }
    }
    return nonOverlapping
}

/// `findRectangles(gray, N = 13, minPerimeter = 50)`: at level 0 the contours of the
/// dilated Canny edges of the median-blurred frame; at levels 1..<N the contours of
/// `gray >= (l + 1) * 255 / N`. Every contour of open perimeter at least `minPerimeter`
/// becomes a rectangle.
///
/// The levels are independent, so they run concurrently (one contour scratch plane per
/// worker) and the rectangles are concatenated in level order, which keeps the tie-breaks
/// downstream (`removeOverlappingRectangles` keeps the first of equals) identical to the
/// sequential C++. Levels whose threshold exceeds the brightest pixel are all-background
/// and are skipped; they can have no contours.
func findRectangles(_ gray: GrayImage, levels: Int = 13, minPerimeter: Double = 50) -> [RectangleDetected] {
    guard levels > 0, gray.width > 0, gray.height > 0 else { return [] }
    let maxGray = Int(gray.pixels.max() ?? 0)
    // find-rectangles.cpp line 87: edges = gray >= (l + 1) * 255 / N  (integer division)
    let levelThresholds: [Int] = [0] + (1..<levels).map { ($0 + 1) * 255 / levels }.filter { $0 <= maxGray }

    // Level 0 (blur, Canny, dilate, and the busiest contour pass) costs as much as several
    // threshold levels, so it gets a worker of its own; the others share the rest.
    let workers = max(1, min(levelThresholds.count, ProcessInfo.processInfo.activeProcessorCount))
    let perLevel = UnsafeMutableBufferPointer<[RectangleDetected]>.allocate(capacity: levelThresholds.count)
    perLevel.initialize(repeating: [])
    defer {
        perLevel.deinitialize()
        perLevel.deallocate()
    }
    // Each worker owns one scratch plane and writes only its own level slots.
    nonisolated(unsafe) let slots = perLevel
    DispatchQueue.concurrentPerform(iterations: workers) { worker in
        var scratch = ContourScratch()
        var level = worker
        let step = workers == 1 ? 1 : workers - 1
        while level < levelThresholds.count {
            let thresholdValue = levelThresholds[level]
            let contours: [Contour]
            if level == 0 {
                // find-rectangles.cpp lines 59-76: cv::medianBlur(gray, grayBlur, 3), then
                // Canny(grayBlur, edges, 253, 255, 5) and a 3x3 dilate to close gaps between
                // edge segments.
                let edges = gray.medianBlur3().canny5(lowThreshold: 253, highThreshold: 255).dilate3()
                contours = findContours(in: edges, scratch: &scratch)
            } else {
                contours = findContours(in: gray, atLeast: thresholdValue, scratch: &scratch)
            }
            var rectangles: [RectangleDetected] = []
            for contour in contours where arcLengthOpen(contour) >= minPerimeter {
                rectangles.append(RectangleDetected(contour: contour, foundAtThreshold: thresholdValue))
            }
            slots[level] = rectangles
            if workers > 1 && worker == 0 { break }
            level += step
        }
    }
    var rectanglesFound: [RectangleDetected] = []
    for level in 0..<levelThresholds.count {
        rectanglesFound.append(contentsOf: perLevel[level])
    }
    return rectanglesFound
}

// MARK: - find-undoverlines.cpp

/// find-undoverlines.cpp lines 20-21: an undoverline's width over its length, with 50% slack.
private let minWidthOverLength: Float = undoverlineWidthAsFractionOfLength / 1.5
private let maxWidthOverLength: Float = undoverlineWidthAsFractionOfLength * 1.5

func isRectangleShapedLikeUndoverline(_ rect: RectangleDetected) -> Bool {
    let shortToLongRatio = rect.shorterSideLength / rect.longerSideLength
    return shortToLongRatio >= minWidthOverLength && shortToLongRatio <= maxWidthOverLength
}

/// `findTighestModalAreaOfRects`: the area at the centre of the tightest cluster of
/// `numberInMode` areas (25 undoverlines of one DiceKey have near-identical areas).
func findTighestModalAreaOfRects(_ rects: [RectangleDetected], numberInMode: Int = 35) -> Float {
    let halfModeSize = max(0, min(rects.count / 2 - 1, numberInMode / 2))
    var areas = rects.map { $0.area }
    areas.sort()
    var tightestModeRange = Float.greatestFiniteMagnitude
    var areaAtTightestMode = Float.nan
    // The last centre whose window fits is count - 1 - halfModeSize. The reference C++
    // subtracts (halfModeSize + 2), which skips the last two centres and, for 26 to 36
    // candidates, every centre, returning NaN.
    let endIndex = areas.count - halfModeSize
    var i = halfModeSize
    while i < endIndex {
        let modeRange = areas[i + halfModeSize] / areas[i - halfModeSize]
        if modeRange < tightestModeRange ||
            // Just in case we found a very tight range of tiny things
            // (e.g., lots of 6x1 boxes that have small total area)
            (modeRange < 1.2 && areas[i] > 3 * areaAtTightestMode) {
            tightestModeRange = modeRange
            areaAtTightestMode = areas[i]
        }
        i += 1
    }
    return areaAtTightestMode
}

/// `findCandidateUndoverlines`: rectangles shaped like undoverlines; when there are more
/// than 25, those within 25% of the modal area, de-duplicated by overlap with a penalty on
/// deviating from the expected shape, the modal area and the modal angle.
func findCandidateUndoverlines(_ gray: GrayImage, levels: Int = 13) -> [RectangleDetected] {
    var candidateUndoverlines = findRectangles(gray, levels: levels).filter(isRectangleShapedLikeUndoverline)

    if candidateUndoverlines.count > 25 {
        let tightestArea = findTighestModalAreaOfRects(candidateUndoverlines)
        let minArea: Float = 0.75 * tightestArea
        let maxArea: Float = tightestArea / 0.75
        candidateUndoverlines = candidateUndoverlines.filter { $0.area >= minArea && $0.area <= maxArea }

        // The modal slope (mod 90, since the lines may sit at any of four rotations).
        let targetAngleInDegrees = findPointOnCircularSignedNumberLineClosestToCenterOfMass(
            candidateUndoverlines.map { $0.angleInDegrees }, 45
        )

        candidateUndoverlines = removeOverlappingRectangles(candidateUndoverlines) { r in
            var deviationFromSideRatio = (r.shorterSideLength / r.longerSideLength) / undoverlineWidthAsFractionOfLength
            if deviationFromSideRatio < 1 && deviationFromSideRatio > 0 {
                deviationFromSideRatio = 1 / deviationFromSideRatio
            }
            deviationFromSideRatio -= 1
            let deviationFromSideLengthRatioPenalty: Float = 2.0 * deviationFromSideRatio
            let deviationFromTargetArea: Float = r.area < tightestArea
                // Falling short of the target area
                ? ((tightestArea / r.area) - 1)
                // Capturing extra area is less serious, so half the penalty
                : (((r.area / tightestArea) - 1) / 2)
            let angleDiff = distanceInModCircularRangeFromNegativeNToN(r.angleInDegrees, targetAngleInDegrees, 90)
            let deviationFromTargetAngle: Float = 2.0 * angleDiff
            return deviationFromSideLengthRatioPenalty + deviationFromTargetArea + deviationFromTargetAngle
        }
    }
    return candidateUndoverlines
}

struct UnderlinesAndOverlines: Sendable {
    var underlines: [Undoverline]
    var overlines: [Undoverline]
}

/// `findReadableUndoverlines`: reads every candidate rectangle and keeps the ones whose
/// 11 bits decode, sorted by the y of the face centre they imply.
func findReadableUndoverlines(_ gray: GrayImage) -> UnderlinesAndOverlines {
    var underlines: [Undoverline] = []
    var overlines: [Undoverline] = []
    for rectEncompassingLine in findCandidateUndoverlines(gray) {
        let undoverline = readUndoverline(gray, rectEncompassingLine: rectEncompassingLine.rotatedRect)
        if undoverline.found && undoverline.determinedIfUnderlineOrOverline {
            if undoverline.isOverline {
                overlines.append(undoverline)
            } else {
                underlines.append(undoverline)
            }
        }
    }
    underlines.sort { $0.inferredCenterOfFace.y < $1.inferredCenterOfFace.y }
    overlines.sort { $0.inferredCenterOfFace.y < $1.inferredCenterOfFace.y }
    return UnderlinesAndOverlines(underlines: underlines, overlines: overlines)
}
