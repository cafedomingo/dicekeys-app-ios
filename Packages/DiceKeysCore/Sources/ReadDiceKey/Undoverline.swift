//
//  Undoverline.swift
//  ReadDiceKey
//
//  An underline or overline read from the image: lib-read-dicekey/undoverline.{h,cpp},
//  the pixel sampling of graphics/sample-point.h, the corner ordering of
//  graphics/rectangle.h (RRectCorners), and `undoverlineRectToLine` / `readUndoverline`
//  from find-undoverlines.cpp.
//

import Foundation

// MARK: - sample-point.h

/// `SampleOffsetsHorizontalFirst`: the pixels around a sample point, nearest first.
private let sampleOffsetsHorizontalFirst: [Point2i] = [
    Point2i(0, 0),
    // 1
    Point2i(1, 0), Point2i(-1, 0), Point2i(0, 1), Point2i(0, -1),
    // 5
    Point2i(1, 1), Point2i(-1, -1), Point2i(1, -1), Point2i(-1, 1),
    // 9
    Point2i(2, 0), Point2i(-2, 0), Point2i(0, 2), Point2i(0, -2),
    // 13
    Point2i(2, -1), Point2i(-2, -1), Point2i(-1, 2), Point2i(-1, -2),
    Point2i(2, 1), Point2i(-2, 1), Point2i(1, 2), Point2i(1, -2)
    // 21
]

/// `SampleOffsetsVerticalFirst`: used for three-pixel samples along horizontal lines.
private let sampleOffsetsVerticalFirst: [Point2i] = [
    Point2i(0, 0), Point2i(0, 1), Point2i(0, -1)
]

/// sample-point.h `getNumberOfPixelsToSample`: how many pixels to take around a sample
/// point given the expected width (in pixels) of the feature being read.
func getNumberOfPixelsToSample(_ physicalPixelWidthPerLogicalPixelWidth: Float) -> Int {
    let w = physicalPixelWidthPerLogicalPixelWidth
    if w < 2.0 { return 1 }
    if w < 3.0 { return 3 }
    if w < 4.0 { return 5 }
    if w < 5.0 { return 9 }
    if w < 5.5 { return 13 }
    return 21
}

/// sample-point.h `samplePoint`: the median of the pixels at and around (x, y); samples
/// outside the image are skipped, and 0 is returned if all were outside.
func samplePoint(_ image: GrayImage, x: Int, y: Int, samplesPerPoint: Int = 21, favorAboveAndBelowOverSides: Bool = false) -> UInt8 {
    let offsets = (samplesPerPoint == 3 && favorAboveAndBelowOverSides) ? sampleOffsetsVerticalFirst : sampleOffsetsHorizontalFirst
    let count = min(samplesPerPoint, offsets.count)
    var values: [UInt8] = []
    values.reserveCapacity(count)
    for s in 0..<count {
        let sx = x + Int(offsets[s].x)
        let sy = y + Int(offsets[s].y)
        if sx < 0 || sy < 0 || sx >= image.width || sy >= image.height {
            continue
        }
        values.append(image[sx, sy])
    }
    if values.isEmpty {
        return 0
    }
    return medianUInt8(&values)
}

/// sample-point.h `samplePointsAlongLine`: samples at fractions of the way from `start` to
/// `end`, each position rounded with C `round()` (half away from zero).
func samplePointsAlongLine(_ image: GrayImage, start: Point2f, end: Point2f, fractions: [Float], samplesPerPoint samplesIn: Int = 0) -> [UInt8] {
    var samplesPerPoint = samplesIn
    if samplesPerPoint <= 0 {
        samplesPerPoint = getNumberOfPixelsToSample(distance2f(start, end) / Float(fractions.count))
    }
    let deltaX = end.x - start.x
    let deltaY = end.y - start.y
    let isMoreHorizontalThanVertical = abs(deltaY) < abs(deltaX)
    return fractions.map { fraction in
        samplePoint(
            image,
            x: cRoundToInt(start.x + fraction * deltaX),
            y: cRoundToInt(start.y + fraction * deltaY),
            samplesPerPoint: samplesPerPoint,
            favorAboveAndBelowOverSides: isMoreHorizontalThanVertical
        )
    }
}

/// sample-point.h `sampledPointsToBits`: first sample is the most significant bit; a sample
/// strictly above the threshold is a 1.
func sampledPointsToBits(_ sampledPoints: [UInt8], thresholdAboveWhichPointIsOneBit: UInt8) -> UInt32 {
    var result: UInt32 = 0
    for value in sampledPoints {
        result <<= 1
        if value > thresholdAboveWhichPointIsOneBit {
            result += 1
        }
    }
    return result
}

// MARK: - rectangle.h RRectCorners

/// The four corners of a rotated rectangle sorted into top-left, top-right, bottom-left and
/// bottom-right. The C++ stores them as integer `cv::Point`s, so they are rounded here too
/// (`cvRound`, half to even), which is what makes undoverline endpoints land on .0 or .5.
struct RRectCorners {
    let topLeft: Point2i
    let topRight: Point2i
    let bottomLeft: Point2i
    let bottomRight: Point2i

    init(_ rrect: RotatedRect) {
        var points = rrect.points()
        var minX = points[0].x, maxX = points[0].x
        var minY = points[0].y, maxY = points[0].y
        for i in 1..<4 {
            minX = min(minX, points[i].x)
            maxX = max(maxX, points[i].x)
            minY = min(minY, points[i].y)
            maxY = max(maxY, points[i].y)
        }
        let width = maxX - minX
        let height = maxY - minY
        let tl: Point2f, tr: Point2f, bl: Point2f, br: Point2f
        if width > height {
            // Sort left to right.
            points.sort { $0.x < $1.x }
            tl = points[0].y < points[1].y ? points[0] : points[1]
            bl = points[0].y < points[1].y ? points[1] : points[0]
            tr = points[2].y < points[3].y ? points[2] : points[3]
            br = points[2].y < points[3].y ? points[3] : points[2]
        } else {
            // Sort top to bottom.
            points.sort { $0.y < $1.y }
            tl = points[0].x < points[1].x ? points[0] : points[1]
            tr = points[0].x < points[1].x ? points[1] : points[0]
            bl = points[2].x < points[3].x ? points[2] : points[3]
            br = points[2].x < points[3].x ? points[3] : points[2]
        }
        topLeft = Point2i(cvRound(tl.x), cvRound(tl.y))
        topRight = Point2i(cvRound(tr.x), cvRound(tr.y))
        bottomLeft = Point2i(cvRound(bl.x), cvRound(bl.y))
        bottomRight = Point2i(cvRound(br.x), cvRound(br.y))
    }
}

@inline(__always)
private func point2f(_ p: Point2i) -> Point2f { Point2f(Float(p.x), Float(p.y)) }

// MARK: - find-undoverlines.cpp: rectangle to line

/// The 31 fractions sampled along a candidate line to find its black/white threshold
/// (`UndoverlineWhiteDarkSamplePoints`).
private let undoverlineWhiteDarkSamplePoints: [Float] = [
    0.0,
    0.03333, 0.0666, 0.1,
    0.13333, 0.1666, 0.2,
    0.23333, 0.2666, 0.3,
    0.33333, 0.3666, 0.4,
    0.43333, 0.4666, 0.5,
    0.53333, 0.5666, 0.6,
    0.63333, 0.6666, 0.7,
    0.73333, 0.7666, 0.8,
    0.83333, 0.8666, 0.9,
    0.93333, 0.9666, 1.0
]

/// find-undoverlines.cpp `undoverlineRectToLine`: the centre line of the rectangle along
/// its long axis, extended 3% and then trimmed back until it starts and ends on dark pixels.
func undoverlineRectToLine(_ image: GrayImage, _ lineBoundaryRect: RotatedRect) -> Line {
    let corners = RRectCorners(lineBoundaryRect)
    let vertical = Line(
        start: midpoint2f(point2f(corners.topLeft), point2f(corners.topRight)),
        end: midpoint2f(point2f(corners.bottomLeft), point2f(corners.bottomRight))
    )
    let horizontal = Line(
        start: midpoint2f(point2f(corners.topLeft), point2f(corners.bottomLeft)),
        end: midpoint2f(point2f(corners.topRight), point2f(corners.bottomRight))
    )
    let isVertical = lineLength(vertical) > lineLength(horizontal)
    let l = isVertical ? vertical : horizontal
    var start = l.start
    var end = l.end
    let dx = end.x - start.x
    let dy = end.y - start.y
    let divisor = max(abs(dx), abs(dy))
    if divisor == 0 {
        return l
    }
    let pixelStepX = dx / divisor
    let pixelStepY = dy / divisor

    // Take 31 samples between start and end to find the threshold between light and dark.
    let sampleSize = getNumberOfPixelsToSample(distance2f(start, end) / Float(undoverlineWhiteDarkSamplePoints.count))
    let pixelSamples = samplePointsAlongLine(image, start: start, end: end, fractions: undoverlineWhiteDarkSamplePoints, samplesPerPoint: sampleSize)
    let whiteBlackThreshold = bimodalThreshold(pixelSamples, minSamplesAtLowMode: 4, minSamplesAtHighMode: 4)

    // Extend start and end 3% in case the rectangle cut off the edge of the line.
    let fractionToExtend: Float = 0.03
    let fractionToExtendH = (end.x - start.x) * fractionToExtend
    let fractionToExtendV = (end.y - start.y) * fractionToExtend
    start.x -= fractionToExtendH
    start.y -= fractionToExtendV
    end.x += fractionToExtendH
    end.y += fractionToExtendV

    // Trim the start by moving it toward the end until it reaches the first dark pixel.
    let oldStart = start
    let oldEnd = end
    let sampleThreeVerticalPoints = !isVertical
    while samplePoint(image, x: cvRound(start.x), y: cvRound(start.y), samplesPerPoint: 3, favorAboveAndBelowOverSides: sampleThreeVerticalPoints) > whiteBlackThreshold
        && isPointBetween2f(start.x + pixelStepX, start.y + pixelStepY, oldStart, oldEnd) {
        start.x += pixelStepX
        start.y += pixelStepY
    }
    // Trim the end likewise.
    while samplePoint(image, x: cvRound(end.x), y: cvRound(end.y), samplesPerPoint: 3, favorAboveAndBelowOverSides: sampleThreeVerticalPoints) > whiteBlackThreshold
        && isPointBetween2f(end.x - pixelStepX, end.y - pixelStepY, start, oldEnd) {
        end.x -= pixelStepX
        end.y -= pixelStepY
    }
    return Line(start: start, end: end)
}

// MARK: - undoverline.{h,cpp}

/// An underline or overline: where it is, which face it encodes, and where that implies
/// the face and its opposite line are.
struct Undoverline: Sendable {
    var found = false
    var determinedIfUnderlineOrOverline = false
    var fromRotatedRect = RotatedRect()
    /// Directed from the letter side of the face to the digit side once decoded.
    var line = Line.zero
    var center = Point2f.zero
    var isOverline = false
    var letterDigitEncoding: UInt8 = 0
    var whiteBlackThreshold: UInt8 = 0
    var inferredCenterOfFace = Point2f.zero
    var inferredOpposingUndoverlineCenter = Point2f.zero
    var faceInferred = FaceSpecification.null
    var inferredOpposingUndoverlineRotatedRect = RotatedRect()

    init() {}

    /// undoverline.cpp `Undoverline::Undoverline(...)`.
    init(fromRotatedRect: RotatedRect, undoverlineStartingAtImageLeft: Line, whiteBlackThreshold: UInt8, binaryCodingReadForwardOrBackward: UInt32) {
        self.fromRotatedRect = fromRotatedRect
        self.whiteBlackThreshold = whiteBlackThreshold
        found = true
        let undoverlineLength = lineLength(undoverlineStartingAtImageLeft)
        let isVertical =
            abs(undoverlineStartingAtImageLeft.end.x - undoverlineStartingAtImageLeft.start.x) <
            abs(undoverlineStartingAtImageLeft.end.y - undoverlineStartingAtImageLeft.start.y)

        let decoded = decodeUndoverline11Bits(binaryCodingReadForwardOrBackward, isVertical: isVertical)
        if !decoded.isValid {
            return
        }
        determinedIfUnderlineOrOverline = true
        isOverline = decoded.isOverline
        letterDigitEncoding = decoded.letterDigitEncoding

        // If the bits were read in reverse order the face is upside down relative to the
        // scan direction; flip the line so it runs from the letter side to the digit side.
        line = decoded.wasReadInReverseOrder ? undoverlineStartingAtImageLeft.reversed : undoverlineStartingAtImageLeft

        faceInferred = DiceKeyFaceSpecification.decodeUndoverlineByte(isOverline: isOverline, letterDigitEncoding)

        let upAngleInRadians = angleOfLineInSignedRadians2f(line) + (decoded.isOverline ? ninetyDegreesAsRadians : -ninetyDegreesAsRadians)
        let cosUpAngleInRadians = cos(upAngleInRadians)
        let sinUpAngleInRadians = sin(upAngleInRadians)

        // Pixels per face edge (faces are square), from the length of this line.
        let pixelsPerElementEdgeLength = Double(undoverlineLength) / Double(FaceDimensionsFractional.undoverlineLength)
        let pixelsFromCenterOfUndoverlineToCenterOfFace = Float(
            Double(FaceDimensionsFractional.centerOfUndoverlineToCenterOfFace) * pixelsPerElementEdgeLength
        )
        let pixelsBetweenCentersOfUndoverlines = 2 * pixelsFromCenterOfUndoverlineToCenterOfFace

        center = midpointOfLine(undoverlineStartingAtImageLeft)
        inferredCenterOfFace = Point2f(
            center.x + pixelsFromCenterOfUndoverlineToCenterOfFace * cosUpAngleInRadians,
            center.y + pixelsFromCenterOfUndoverlineToCenterOfFace * sinUpAngleInRadians
        )
        inferredOpposingUndoverlineCenter = Point2f(
            fromRotatedRect.center.x + pixelsBetweenCentersOfUndoverlines * cosUpAngleInRadians,
            fromRotatedRect.center.y + pixelsBetweenCentersOfUndoverlines * sinUpAngleInRadians
        )
        inferredOpposingUndoverlineRotatedRect = RotatedRect(
            center: inferredOpposingUndoverlineCenter,
            size: fromRotatedRect.size,
            angle: fromRotatedRect.angle
        )
    }
}

/// find-undoverlines.cpp `readUndoverline`: reads the 11 dots along the rectangle's centre
/// line, thresholds them so at least four are black and four are white, and decodes them.
func readUndoverline(_ image: GrayImage, rectEncompassingLine: RotatedRect) -> Undoverline {
    let undoverlineStartingAtImageLeft = undoverlineRectToLine(image, rectEncompassingLine)
    let medianPixelValues = samplePointsAlongLine(
        image,
        start: undoverlineStartingAtImageLeft.start,
        end: undoverlineStartingAtImageLeft.end,
        fractions: FaceDimensionsFractional.dotCentersAsFractionOfUndoverline
    )
    let whiteBlackThreshold = bimodalThreshold(
        medianPixelValues,
        minSamplesAtLowMode: DiceKeyFaceSpecification.minNumberOfBlackDotsInUndoverline,
        minSamplesAtHighMode: DiceKeyFaceSpecification.minNumberOfWhiteDotsInUndoverline
    )
    let binaryCodingReadForwardOrBackward = sampledPointsToBits(medianPixelValues, thresholdAboveWhichPointIsOneBit: whiteBlackThreshold)
    return Undoverline(
        fromRotatedRect: rectEncompassingLine,
        undoverlineStartingAtImageLeft: undoverlineStartingAtImageLeft,
        whiteBlackThreshold: whiteBlackThreshold,
        binaryCodingReadForwardOrBackward: binaryCodingReadForwardOrBackward
    )
}
