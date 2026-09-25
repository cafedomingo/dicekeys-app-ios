//
//  Geometry.swift
//  ReadDiceKey
//
//  Points, lines, rotated rectangles and the angle helpers of the C++ scanner
//  (lib-read-dicekey/graphics/geometry.h and the OpenCV types it leans on).
//  Everything is a plain value type; `Float` where the C++ used `float`, `Double`
//  where it used `double`, so the arithmetic rounds the same way.
//

import Foundation

/// `cv::Point2f`.
struct Point2f: Sendable, Equatable {
    var x: Float
    var y: Float

    init(_ x: Float, _ y: Float) {
        self.x = x
        self.y = y
    }

    static let zero = Point2f(0, 0)
}

/// `cv::Point` (integer pixel coordinates).
struct Point2i: Sendable, Equatable {
    var x: Int32
    var y: Int32

    init(_ x: Int32, _ y: Int32) {
        self.x = x
        self.y = y
    }

    init(_ x: Int, _ y: Int) {
        self.x = Int32(x)
        self.y = Int32(y)
    }
}

/// `cv::Size2f`.
struct Size2f: Sendable, Equatable {
    var width: Float
    var height: Float

    init(_ width: Float, _ height: Float) {
        self.width = width
        self.height = height
    }

    static let zero = Size2f(0, 0)
}

/// A directed line from `start` to `end` (geometry.h `Line`).
struct Line: Sendable, Equatable {
    var start: Point2f
    var end: Point2f

    static let zero = Line(start: .zero, end: .zero)

    /// geometry.h `reverseLineDirection`.
    var reversed: Line { Line(start: end, end: start) }
}

// MARK: - OpenCV rounding

/// Saturation bounds for the integer conversions (2^31 is exactly representable as Float).
private let int32MaxAsFloat: Float = 2_147_483_648
private let int32MinAsFloat: Float = -2_147_483_648

/// OpenCV's `cvRound` on arm64 and x86-64: round half to even (`lrint`). Used wherever the
/// C++ converts a `Point2f` to an integer `Point` implicitly (`saturate_cast<int>`).
/// Non-finite input, undefined in C++, maps to 0 here so nothing traps.
@inline(__always)
func cvRound(_ value: Float) -> Int {
    guard value.isFinite else { return 0 }
    let rounded = value.rounded(.toNearestOrEven)
    if rounded >= int32MaxAsFloat { return Int(Int32.max) }
    if rounded <= int32MinAsFloat { return Int(Int32.min) }
    return Int(rounded)
}

@inline(__always)
func cvRound(_ value: Double) -> Int {
    guard value.isFinite else { return 0 }
    let rounded = value.rounded(.toNearestOrEven)
    if rounded >= 2_147_483_647 { return Int(Int32.max) }
    if rounded <= -2_147_483_648 { return Int(Int32.min) }
    return Int(rounded)
}

/// C's `round()` (half away from zero) followed by `int(...)`, as in `int(round(x))`.
@inline(__always)
func cRoundToInt(_ value: Float) -> Int {
    guard value.isFinite else { return 0 }
    let rounded = value.rounded(.toNearestOrAwayFromZero)
    if rounded >= int32MaxAsFloat { return Int(Int32.max) }
    if rounded <= int32MinAsFloat { return Int(Int32.min) }
    return Int(rounded)
}

/// `cvFloor`.
@inline(__always)
func cvFloor(_ value: Double) -> Int {
    guard value.isFinite else { return 0 }
    return Int(value.rounded(.down))
}

// MARK: - Rotated rectangle

/// `cv::RotatedRect`: a center, a size (width, height) and an angle in degrees.
///
/// The angle convention matches OpenCV 4.5.1 and later (`minAreaRect` returns angles in
/// [0, 90)); the scanner only ever uses the angle modulo 90 or through `points()`, so the
/// convention just has to be internally consistent.
struct RotatedRect: Sendable, Equatable {
    var center: Point2f
    var size: Size2f
    var angle: Float

    init() {
        center = .zero
        size = .zero
        angle = 0
    }

    init(center: Point2f, size: Size2f, angle: Float) {
        self.center = center
        self.size = size
        self.angle = angle
    }

    /// The four corners, exactly as `cv::RotatedRect::points` computes them.
    func points() -> [Point2f] {
        let radians = Double(angle) * Double.pi / 180.0
        let b = Float(cos(radians)) * 0.5
        let a = Float(sin(radians)) * 0.5
        let p0 = Point2f(
            center.x - a * size.height - b * size.width,
            center.y + b * size.height - a * size.width
        )
        let p1 = Point2f(
            center.x + a * size.height - b * size.width,
            center.y - b * size.height - a * size.width
        )
        let p2 = Point2f(2 * center.x - p0.x, 2 * center.y - p0.y)
        let p3 = Point2f(2 * center.x - p1.x, 2 * center.y - p1.y)
        return [p0, p1, p2, p3]
    }
}

// MARK: - geometry.h

let multToGetRadiansFromDegrees: Double = (2 * Double.pi) / 360.0
let multToGetDegreesFromRadians: Double = 360.0 / (2 * Double.pi)

@inline(__always)
func radiansToDegrees(_ r: Float) -> Float { Float(Double(r) * multToGetDegreesFromRadians) }

@inline(__always)
func degreesToRadians(_ d: Float) -> Float { Float(Double(d) * multToGetRadiansFromDegrees) }

/// geometry.h `distance2f(x, y)`.
@inline(__always)
func distance2f(_ x: Float, _ y: Float) -> Float { (x * x + y * y).squareRoot() }

/// geometry.h `distance2f(a, b)`.
@inline(__always)
func distance2f(_ a: Point2f, _ b: Point2f) -> Float { distance2f(a.x - b.x, a.y - b.y) }

@inline(__always)
func lineLength(_ line: Line) -> Float { distance2f(line.start, line.end) }

@inline(__always)
func midpoint2f(_ a: Point2f, _ b: Point2f) -> Point2f {
    Point2f((a.x + b.x) / 2.0, (a.y + b.y) / 2.0)
}

@inline(__always)
func midpointOfLine(_ line: Line) -> Point2f { midpoint2f(line.start, line.end) }

/// geometry.h `isPointBetween2f`.
@inline(__always)
func isPointBetween2f(_ x: Float, _ y: Float, _ bound1: Point2f, _ bound2: Point2f) -> Bool {
    x >= min(bound1.x, bound2.x) && x <= max(bound1.x, bound2.x)
        && y >= min(bound1.y, bound2.y) && y <= max(bound1.y, bound2.y)
}

/// geometry.h `angleOfLineInSignedRadians2f`: `atan2` in double, narrowed to float.
@inline(__always)
func angleOfLineInSignedRadians2f(_ start: Point2f, _ end: Point2f) -> Float {
    let deltaX = end.x - start.x
    let deltaY = end.y - start.y
    return Float(atan2(Double(deltaY), Double(deltaX)))
}

@inline(__always)
func angleOfLineInSignedRadians2f(_ line: Line) -> Float {
    angleOfLineInSignedRadians2f(line.start, line.end)
}

@inline(__always)
func angleOfLineInSignedDegrees2f(_ line: Line) -> Float {
    radiansToDegrees(angleOfLineInSignedRadians2f(line))
}

let ninetyDegreesAsRadians = Float(90.0 * multToGetRadiansFromDegrees)
let fortyFiveDegreesAsRadians = Float(45.0 * multToGetRadiansFromDegrees)

/// geometry.h `radiansFromRightAngle`: the distance to the nearest multiple of 90 degrees.
@inline(__always)
func radiansFromRightAngle(_ angleInRadians: Float) -> Float {
    reduceToSignedRange(angleInRadians, fortyFiveDegreesAsRadians)
}

/// geometry.h `rotatePointCounterclockwiseAroundOrigin`.
@inline(__always)
func rotatePointCounterclockwiseAroundOrigin(_ point: Point2f, _ angleInRadians: Float) -> Point2f {
    let s = sin(angleInRadians)
    let c = cos(angleInRadians)
    return Point2f(point.x * c - point.y * s, point.x * s + point.y * c)
}

/// geometry.h `rotatePointCounterclockwise`.
func rotatePointCounterclockwise(_ point: Point2f, around center: Point2f, _ angleInRadians: Float) -> Point2f {
    let relative = Point2f(point.x - center.x, point.y - center.y)
    let rotated = rotatePointCounterclockwiseAroundOrigin(relative, angleInRadians)
    return Point2f(rotated.x + center.x, rotated.y + center.y)
}

/// geometry.h `rotatePointClockwise`.
func rotatePointClockwise(_ point: Point2f, around center: Point2f, _ angleInRadians: Float) -> Point2f {
    rotatePointCounterclockwise(point, around: center, -angleInRadians)
}

/// geometry.h `GridProximity`: distance of points from the row and column lines through
/// a face center at the grid's angle.
struct GridProximity: Sendable {
    private let rowDx: Float
    private let rowDy: Float
    private let columnDx: Float
    private let columnDy: Float
    private let rowThirdAndFourthTerm: Float
    private let columnThirdAndFourthTerm: Float

    init(centerOfElement: Point2f, angleInRadians: Float) {
        let rowAngleRadians = radiansFromRightAngle(angleInRadians)
        let columnAngleRadians = Float(Double(rowAngleRadians) + Double.pi / 2)
        rowDx = cos(rowAngleRadians)
        rowDy = sin(rowAngleRadians)
        columnDx = cos(columnAngleRadians)
        columnDy = sin(columnAngleRadians)
        let x1 = centerOfElement.x
        let y1 = centerOfElement.y
        let rowX2 = x1 + rowDx
        let rowY2 = y1 + rowDy
        let columnX2 = x1 + columnDx
        let columnY2 = y1 + columnDy
        rowThirdAndFourthTerm = rowX2 * y1 - rowY2 * x1
        columnThirdAndFourthTerm = columnX2 * y1 - columnY2 * x1
    }

    func pixelDistanceFromRow(_ p: Point2f) -> Float {
        abs((rowDy * p.x) - (rowDx * p.y) + rowThirdAndFourthTerm)
    }

    func pixelDistanceFromColumn(_ p: Point2f) -> Float {
        abs((columnDy * p.x) - (columnDx * p.y) + columnThirdAndFourthTerm)
    }
}
