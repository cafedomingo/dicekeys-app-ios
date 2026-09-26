//
//  Contours.swift
//  ReadDiceKey
//
//  The contour side of OpenCV that graphics/find-rectangles.cpp and graphics/rectangle.h
//  rely on, implemented directly:
//
//    findContours(RETR_LIST, CHAIN_APPROX_SIMPLE) -> findContours(in:)
//    arcLength(contour, closed: false)            -> arcLengthOpen(_:)
//    contourArea                                  -> contourArea(_:)
//    minAreaRect                                  -> minAreaRect(_:)
//    pointPolygonTest(measureDist: false)         -> pointPolygonTest(_:_:)
//
//  Contour tracing is Suzuki and Abe's border following (the algorithm behind
//  cv::findContours): every outer border and every hole border of the 8-connected
//  foreground, with a zero border around the image, compressed to the pixels where the
//  chain direction changes. Vision's VNDetectContoursRequest was not used because it
//  applies its own preprocessing and simplification and returns normalized coordinates,
//  so its rectangles would not match the C++ scanner's.
//

import Foundation

/// A traced border: the pixels where its chain direction changes, in tracing order.
typealias Contour = [Point2i]

// MARK: - findContours

// Direction codes as OpenCV uses them: 0 right, then counter-clockwise on screen
// (1 up-right, 2 up, 3 up-left, 4 left, 5 down-left, 6 down, 7 down-right); the tracer
// keeps them as offsets into the label plane.

/// Scratch memory for `findContours`, reused across the binarisations of a frame so the
/// label plane is allocated once per worker instead of once per level.
struct ContourScratch: Sendable {
    fileprivate var labels: [Int32] = []
}

/// Finds every border of the non-zero pixels of `binary` (outer borders and holes alike),
/// each compressed as CHAIN_APPROX_SIMPLE does. Pixels outside the image count as zero.
/// The list is in the order `cv::findContours` reports (most recently traced first).
func findContours(in binary: GrayImage) -> [Contour] {
    var scratch = ContourScratch()
    return findContours(in: binary, scratch: &scratch)
}

func findContours(in binary: GrayImage, scratch: inout ContourScratch) -> [Contour] {
    findContours(in: binary, atLeast: 1, scratch: &scratch)
}

/// `findContours` of the binarisation `image >= threshold`, without materialising it: the
/// comparison is done while filling the label plane. With `threshold` 1 this is the plain
/// contour search of a binary image.
func findContours(in image: GrayImage, atLeast threshold: Int, scratch: inout ContourScratch) -> [Contour] {
    let w = image.width, h = image.height
    guard w > 0 && h > 0 else { return [] }
    let stride = w + 2
    let labelCount = stride * (h + 2)
    // Label image with a zero border: 0 background, 1 unvisited foreground, otherwise the
    // signed border number (Suzuki's NBD) of the border the pixel belongs to. The border
    // is never written by the tracer, so a reused buffer only needs its interior refilled.
    if scratch.labels.count != labelCount {
        scratch.labels = [Int32](repeating: 0, count: labelCount)
    }
    let t = UInt8(clamping: threshold)
    image.pixels.withUnsafeBufferPointer { srcBuf in
        scratch.labels.withUnsafeMutableBufferPointer { fBuf in
            guard let src = srcBuf.baseAddress, let f = fBuf.baseAddress else { return }
            for y in 0..<h {
                let s = src + y * w
                let d = f + (y + 1) * stride + 1
                for x in 0..<w {
                    d[x] = s[x] >= t ? 1 : 0
                }
            }
        }
    }
    var contours: [Contour] = []
    var nbd: Int32 = 1
    // Neighbour offsets in the label plane for direction codes 0...7.
    let offsets: [Int] = [1, -stride + 1, -stride, -stride - 1, -1, stride - 1, stride, stride + 1]
    scratch.labels.withUnsafeMutableBufferPointer { fBuf in
        offsets.withUnsafeBufferPointer { off in
            guard let f = fBuf.baseAddress else { return }
            var points: [Point2i] = []
            for y in 1...h {
                let row = y * stride
                for x in 1...w {
                    let p = row + x
                    let v = f[p]
                    if v == 0 { continue }
                    let startDir: Int
                    if v == 1 && f[p - 1] == 0 {
                        startDir = 4  // outer border: the clockwise search starts at the left neighbour
                    } else if v >= 1 && f[p + 1] == 0 {
                        startDir = 0  // hole border: it starts at the right neighbour
                    } else {
                        continue
                    }
                    nbd += 1
                    // Step 3.1: clockwise search (decreasing direction index) for a non-zero neighbour.
                    var found = false
                    var firstDirection = 0
                    var i1 = 0
                    for k in 0..<8 {
                        let d = (startDir - k) & 7
                        let n = p + off[d]
                        if f[n] != 0 {
                            firstDirection = d
                            i1 = n
                            found = true
                            break
                        }
                    }
                    if !found {
                        // An isolated pixel is a border on its own.
                        f[p] = -nbd
                        contours.append([Point2i(x - 1, y - 1)])
                        continue
                    }
                    points.removeAll(keepingCapacity: true)
                    var i3 = p                    // current pixel (index in the label plane)
                    var backDir = firstDirection  // direction from the current pixel to the previous one
                    var prevDir = -1              // step direction we arrived by (-1 at the start)
                    var outgoingFromStart = -1
                    while true {
                        // Step 3.3: counter-clockwise search (increasing index) starting after backDir.
                        var d = backDir
                        var i4 = 0
                        var sawRightZero = false
                        for k in 1...8 {
                            d = (backDir + k) & 7
                            let n = i3 + off[d]
                            if f[n] != 0 {
                                i4 = n
                                break
                            }
                            if d == 0 { sawRightZero = true }
                        }
                        // Step 3.4: label the current pixel.
                        if sawRightZero {
                            f[i3] = -nbd
                        } else if f[i3] == 1 {
                            f[i3] = nbd
                        }
                        // CHAIN_APPROX_SIMPLE keeps a pixel only where the direction changes. The start
                        // pixel's incoming direction is known at the end, so it is decided there.
                        if prevDir == -1 {
                            outgoingFromStart = d
                        } else if prevDir != d {
                            points.append(Point2i(i3 % stride - 1, i3 / stride - 1))
                        }
                        // Step 3.5: back at the start, entering it from the same first neighbour.
                        if i4 == p && i3 == i1 {
                            if d != outgoingFromStart {
                                points.insert(Point2i(x - 1, y - 1), at: 0)
                            }
                            break
                        }
                        prevDir = d
                        i3 = i4
                        backDir = (d + 4) & 7
                    }
                    contours.append(points)
                }
            }
        }
    }
    // OpenCV links each new border at the front of its list.
    contours.reverse()
    return contours
}

// MARK: - Measures

/// `cv::arcLength(contour, false)`: the polyline length without the closing segment.
func arcLengthOpen(_ contour: Contour) -> Double {
    let n = contour.count
    if n < 2 { return 0 }
    var total = 0.0
    for i in 0..<(n - 1) {
        let a = contour[i], b = contour[i + 1]
        let dx = Double(b.x) - Double(a.x)
        let dy = Double(b.y) - Double(a.y)
        total += (dx * dx + dy * dy).squareRoot()
    }
    return total
}

/// `cv::contourArea` (shoelace formula, absolute value).
func contourArea(_ contour: Contour) -> Double {
    let n = contour.count
    if n == 0 { return 0 }
    var a00 = 0.0
    var prev = contour[n - 1]
    for p in contour {
        a00 += Double(prev.x) * Double(p.y) - Double(prev.y) * Double(p.x)
        prev = p
    }
    return abs(a00 * 0.5)
}

// MARK: - Convex hull and minimum-area rectangle

/// Convex hull by Andrew's monotone chain, without collinear points, in clockwise order
/// on screen (y down), the order `cv::convexHull(..., clockwise: true)` produces.
func convexHull(_ contour: Contour) -> [Point2f] {
    var p = contour
    p.sort { a, b in a.x < b.x || (a.x == b.x && a.y < b.y) }
    // Drop duplicates.
    var unique: [Point2i] = []
    unique.reserveCapacity(p.count)
    for q in p where unique.last != q {
        unique.append(q)
    }
    p = unique
    let n = p.count
    if n < 3 {
        return p.map { Point2f(Float($0.x), Float($0.y)) }
    }
    @inline(__always) func cross(_ o: Point2i, _ a: Point2i, _ b: Point2i) -> Int64 {
        Int64(a.x - o.x) * Int64(b.y - o.y) - Int64(a.y - o.y) * Int64(b.x - o.x)
    }
    var hull = [Point2i](repeating: Point2i(0, 0), count: 2 * n)
    var k = 0
    for i in 0..<n {
        while k >= 2 && cross(hull[k - 2], hull[k - 1], p[i]) <= 0 { k -= 1 }
        hull[k] = p[i]
        k += 1
    }
    let t = k + 1
    var i = n - 1
    while i > 0 {
        while k >= t && cross(hull[k - 2], hull[k - 1], p[i - 1]) <= 0 { k -= 1 }
        hull[k] = p[i - 1]
        k += 1
        i -= 1
    }
    return hull[0..<(k - 1)].map { Point2f(Float($0.x), Float($0.y)) }
}

/// `cv::minAreaRect`: the smallest rectangle (any rotation) enclosing the points. It is
/// found by rotating calipers over the convex hull: for each hull edge, the bounding box
/// aligned with it; the smallest wins. The angle is normalised to [0, 90) as OpenCV 4.5.1+
/// does (swapping width and height when rotating by 90 degrees).
///
/// When two edges give exactly the same area OpenCV's calipers may pick the other one; the
/// rectangle then differs by a rotation of the same box, which the scanner tolerates.
func minAreaRect(_ contour: Contour) -> RotatedRect {
    var box = RotatedRect()
    let hull = convexHull(contour)
    let n = hull.count
    if n == 0 { return box }
    if n == 1 {
        box.center = hull[0]
        return box
    }
    if n == 2 {
        box.center = Point2f((hull[0].x + hull[1].x) * 0.5, (hull[0].y + hull[1].y) * 0.5)
        let dx = Double(hull[1].x - hull[0].x), dy = Double(hull[1].y - hull[0].y)
        box.size = Size2f(Float((dx * dx + dy * dy).squareRoot()), 0)
        box.angle = Float(atan2(dy, dx) * 180 / Double.pi)
        return normalizedMinAreaRect(box)
    }
    var minArea = Float.greatestFiniteMagnitude
    var bestUx: Float = 1, bestUy: Float = 0
    var bestMinU: Float = 0, bestMaxU: Float = 0, bestMinN: Float = 0, bestMaxN: Float = 0
    for i in 0..<n {
        let a = hull[i]
        let b = hull[(i + 1) % n]
        let dx = Double(b.x - a.x), dy = Double(b.y - a.y)
        let len = (dx * dx + dy * dy).squareRoot()
        if len == 0 { continue }
        let ux = Float(dx / len), uy = Float(dy / len)
        let nx = -uy, ny = ux
        var minU = Float.greatestFiniteMagnitude, maxU = -Float.greatestFiniteMagnitude
        var minN = Float.greatestFiniteMagnitude, maxN = -Float.greatestFiniteMagnitude
        for q in hull {
            let pu = q.x * ux + q.y * uy
            let pn = q.x * nx + q.y * ny
            if pu < minU { minU = pu }
            if pu > maxU { maxU = pu }
            if pn < minN { minN = pn }
            if pn > maxN { maxN = pn }
        }
        let area = (maxU - minU) * (maxN - minN)
        if area <= minArea {
            minArea = area
            bestUx = ux
            bestUy = uy
            bestMinU = minU
            bestMaxU = maxU
            bestMinN = minN
            bestMaxN = maxN
        }
    }
    let cu = (bestMinU + bestMaxU) * 0.5
    let cn = (bestMinN + bestMaxN) * 0.5
    let nx = -bestUy, ny = bestUx
    box.center = Point2f(cu * bestUx + cn * nx, cu * bestUy + cn * ny)
    box.size = Size2f(bestMaxU - bestMinU, bestMaxN - bestMinN)
    box.angle = Float(atan2(Double(bestUy), Double(bestUx)) * 180 / Double.pi)
    return normalizedMinAreaRect(box)
}

private func normalizedMinAreaRect(_ input: RotatedRect) -> RotatedRect {
    var box = input
    guard box.angle.isFinite else { return box }
    while box.angle < 0 {
        box.angle += 90
        box.size = Size2f(box.size.height, box.size.width)
    }
    while box.angle >= 90 {
        box.angle -= 90
        box.size = Size2f(box.size.height, box.size.width)
    }
    return box
}

// MARK: - Point in polygon

/// `cv::pointPolygonTest(contour, pt, measureDist: false)` for a float polygon:
/// +1 inside, -1 outside, 0 on an edge or vertex.
func pointPolygonTest(_ contour: [Point2f], _ pt: Point2f) -> Double {
    let total = contour.count
    if total == 0 { return -1 }
    var counter = 0
    var v = contour[total - 1]
    for i in 0..<total {
        let v0 = v
        v = contour[i]
        if (v0.y <= pt.y && v.y <= pt.y) || (v0.y > pt.y && v.y > pt.y) || (v0.x < pt.x && v.x < pt.x) {
            if pt.y == v.y && (pt.x == v.x || (pt.y == v0.y && ((v0.x <= pt.x && pt.x <= v.x) || (v.x <= pt.x && pt.x <= v0.x)))) {
                return 0
            }
            continue
        }
        var dist = Double(pt.y - v0.y) * Double(v.x - v0.x) - Double(pt.x - v0.x) * Double(v.y - v0.y)
        if dist == 0 { return 0 }
        if v.y < v0.y { dist = -dist }
        if dist > 0 { counter += 1 }
    }
    return counter % 2 == 0 ? -1 : 1
}
