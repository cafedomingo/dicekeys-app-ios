//
//  Borders.swift
//  ReadDiceKey
//
//  Border following (Suzuki and Abe, 1985) over a thresholded image, and the smallest
//  rectangle around a border. Every outer border and every hole border of the 8-connected
//  bright pixels is traced and compressed to the pixels where the chain turns.
//

import simd

/// A pixel position.
typealias PixelPoint = SIMD2<Int32>

/// A traced border: the pixels where its chain direction changes, in tracing order.
typealias Border = [PixelPoint]

// Direction codes: 0 right, then counter-clockwise on screen (1 up-right, 2 up, 3 up-left,
// 4 left, 5 down-left, 6 down, 7 down-right); the tracer keeps them as offsets into the
// label plane.

/// Every border (outer borders and holes alike) of the pixels at least as bright as
/// `threshold`, with pixels outside the image counting as dark. The comparison is made
/// while filling the label plane, so the binary image is never stored.
///
/// Returns only borders whose `perimeter` is at least `minPerimeter`. Shorter ones are
/// still traced, because their labels shape the borders found after them.
func traceBorders(in image: GrayImage, atLeast threshold: UInt8, minPerimeter: Double) -> [Border] {
    let w = image.width, h = image.height
    guard w > 0 && h > 0 else { return [] }
    let stride = w + 2
    let labelCount = stride * (h + 2)
    // Label plane with a dark frame around the image: 0 dark, 1 bright, 2 on a traced
    // border, and -2 on a traced border with dark to its right, where no hole border may
    // start again.
    var labels = [Int8](repeating: 0, count: labelCount)
    image.pixels.withUnsafeBufferPointer { srcBuf in
        labels.withUnsafeMutableBufferPointer { fBuf in
            guard let src = srcBuf.baseAddress, let f = fBuf.baseAddress else { return }
            for y in 0..<h {
                let s = src + y * w
                let d = f + (y + 1) * stride + 1
                for x in 0..<w {
                    d[x] = s[x] >= threshold ? 1 : 0
                }
            }
        }
    }
    var borders: [Border] = []
    // Neighbor offsets in the label plane for direction codes 0...7.
    let offsets: [Int] = [1, -stride + 1, -stride, -stride - 1, -1, stride - 1, stride, stride + 1]
    labels.withUnsafeMutableBufferPointer { fBuf in
        offsets.withUnsafeBufferPointer { off in
            guard let f = fBuf.baseAddress else { return }
            var points: [PixelPoint] = []
            for y in 1...h {
                let row = y * stride
                for x in 1...w {
                    let p = row + x
                    let v = f[p]
                    if v == 0 { continue }
                    let startDir: Int
                    if v == 1 && f[p - 1] == 0 {
                        startDir = 4  // outer border: the clockwise search starts at the left neighbor
                    } else if v >= 1 && f[p + 1] == 0 {
                        startDir = 0  // hole border: it starts at the right neighbor
                    } else {
                        continue
                    }
                    // Step 3.1: clockwise search (decreasing direction index) for a non-zero neighbor.
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
                        // An isolated pixel is a border of length zero.
                        f[p] = -2
                        continue
                    }
                    points.removeAll(keepingCapacity: true)
                    var i3 = p                    // current pixel (index in the label plane)
                    var backDir = firstDirection  // direction from the current pixel to the previous one
                    var prevDir = -1              // step direction we arrived by (-1 at the start)
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
                            f[i3] = -2
                        } else if f[i3] == 1 {
                            f[i3] = 2
                        }
                        // The start pixel and every pixel where the direction changes are kept.
                        if prevDir != d {
                            points.append(PixelPoint(Int32(i3 % stride - 1), Int32(i3 / stride - 1)))
                        }
                        // Step 3.5: back at the start, entering it from the same first neighbor.
                        if i4 == p && i3 == i1 {
                            break
                        }
                        prevDir = d
                        i3 = i4
                        backDir = (d + 4) & 7
                    }
                    if perimeter(points) < minPerimeter { continue }
                    // Exact size: storing `points` itself would give every later border the
                    // longest border's capacity.
                    borders.append(Border(unsafeUninitializedCapacity: points.count) { buffer, count in
                        count = buffer.initialize(fromContentsOf: points)
                    })
                }
            }
        }
    }
    return borders
}

// MARK: - Measures

/// The length of the closed polygon through the points.
func perimeter(_ border: Border) -> Double {
    guard var previous = border.last else { return 0 }
    var total = 0.0
    for point in border {
        total += simd_distance(SIMD2<Double>(previous), SIMD2<Double>(point))
        previous = point
    }
    return total
}

// MARK: - Minimum-area rectangle

/// Convex hull by Andrew's monotone chain, without collinear points.
private func convexHull(_ border: Border) -> [Point] {
    var p = border
    p.sort { a, b in a.x < b.x || (a.x == b.x && a.y < b.y) }
    var unique: [PixelPoint] = []
    unique.reserveCapacity(p.count)
    for q in p where unique.last != q {
        unique.append(q)
    }
    p = unique
    let n = p.count
    if n < 3 {
        return p.map { Point(Float($0.x), Float($0.y)) }
    }
    @inline(__always) func cross(_ o: PixelPoint, _ a: PixelPoint, _ b: PixelPoint) -> Int64 {
        Int64(a.x - o.x) * Int64(b.y - o.y) - Int64(a.y - o.y) * Int64(b.x - o.x)
    }
    var hull = [PixelPoint](repeating: .zero, count: 2 * n)
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
    return hull[0..<(k - 1)].map { Point(Float($0.x), Float($0.y)) }
}

/// The smallest rectangle, at any rotation, around the points. One side of it always lies
/// along an edge of the convex hull, so each edge's aligned bounding box is measured and
/// the smallest kept (rotating calipers). Nil when the points do not span a line.
func smallestRectangle(around border: Border) -> Bar? {
    let hull = convexHull(border)
    var best: (area: Float, along: Point, minU: Float, maxU: Float, minN: Float, maxN: Float)?
    for i in hull.indices {
        let edge = hull[(i + 1) % hull.count] - hull[i]
        guard edge != .zero else { continue }
        let along = simd_normalize(edge)
        let across = along.turnedClockwise
        var minU = Float.greatestFiniteMagnitude, maxU = -Float.greatestFiniteMagnitude
        var minN = Float.greatestFiniteMagnitude, maxN = -Float.greatestFiniteMagnitude
        for q in hull {
            let u = simd_dot(q, along), n = simd_dot(q, across)
            minU = min(minU, u)
            maxU = max(maxU, u)
            minN = min(minN, n)
            maxN = max(maxN, n)
        }
        let area = (maxU - minU) * (maxN - minN)
        if area < best?.area ?? .greatestFiniteMagnitude {
            best = (area, along, minU, maxU, minN, maxN)
        }
    }
    guard let best else { return nil }
    let across = best.along.turnedClockwise
    let center = best.along * (best.minU + best.maxU) / 2 + across * (best.minN + best.maxN) / 2
    let extentAlong = best.maxU - best.minU, extentAcross = best.maxN - best.minN
    return extentAlong >= extentAcross
        ? Bar(center: center, axis: best.along, length: extentAlong, width: extentAcross)
        : Bar(center: center, axis: across, length: extentAcross, width: extentAlong)
}
