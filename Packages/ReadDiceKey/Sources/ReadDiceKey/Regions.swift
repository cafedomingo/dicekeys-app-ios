//
//  Regions.swift
//  ReadDiceKey
//
//  The dark regions of a thresholded image, found by joining runs of dark pixels that touch,
//  and the smallest rectangle around a region.
//

import simd

/// A pixel position.
typealias PixelPoint = SIMD2<Int32>

/// The 4-connected regions of pixels darker than `threshold` that have at least `minPixels`
/// pixels. A region is given by both ends of every run of dark pixels it has in a row, which
/// is all its convex hull needs.
func darkRegions(in image: GrayImage, darkerThan threshold: UInt8, minPixels: Int) -> [[PixelPoint]] {
    var runs: [Run] = []
    var parents = Parents()
    image.pixels.withUnsafeBufferPointer { pixels in
        var above = 0..<0  // the runs in the row above
        for y in 0..<image.height {
            let row = pixels.baseAddress! + y * image.width
            let first = runs.count
            var candidate = above.lowerBound
            var x = 0
            while x < image.width {
                guard row[x] < threshold else {
                    x += 1
                    continue
                }
                let start = x
                while x < image.width, row[x] < threshold { x += 1 }
                let run = Run(start: Int32(start), end: Int32(x - 1), y: Int32(y))
                let index = parents.add()
                runs.append(run)
                // Join every run above that shares a column with this one.
                while candidate < above.upperBound, runs[candidate].end < run.start { candidate += 1 }
                var other = candidate
                while other < above.upperBound, runs[other].start <= run.end {
                    parents.join(index, Int32(other))
                    other += 1
                }
            }
            above = first..<runs.count
        }
    }

    var pixelCount = [Int](repeating: 0, count: runs.count)
    var roots = [Int](repeating: 0, count: runs.count)
    for (index, run) in runs.enumerated() {
        roots[index] = Int(parents.root(Int32(index)))
        pixelCount[roots[index]] += Int(run.end - run.start + 1)
    }
    var regionOfRoot = [Int](repeating: -1, count: runs.count)
    var regions: [[PixelPoint]] = []
    for (index, run) in runs.enumerated() where pixelCount[roots[index]] >= minPixels {
        let root = roots[index]
        if regionOfRoot[root] < 0 {
            regionOfRoot[root] = regions.count
            regions.append([])
        }
        // The corners of the run's pixels, so the hull is the region's outline, not the
        // outline of its pixel centers.
        let region = regionOfRoot[root]
        regions[region].append(PixelPoint(run.start, run.y))
        regions[region].append(PixelPoint(run.end + 1, run.y))
        regions[region].append(PixelPoint(run.start, run.y + 1))
        regions[region].append(PixelPoint(run.end + 1, run.y + 1))
    }
    return regions
}

/// A row's stretch of consecutive dark pixels, `start` to `end` inclusive.
private struct Run {
    let start: Int32
    let end: Int32
    let y: Int32
}

/// Which runs belong together: a union-find over run indices.
private struct Parents {
    private var parent: [Int32] = []

    /// Adds a run in a region of its own and returns its index.
    mutating func add() -> Int32 {
        parent.append(Int32(parent.count))
        return Int32(parent.count - 1)
    }

    /// The run that stands for the whole region `run` is in.
    mutating func root(_ run: Int32) -> Int32 {
        var run = run
        while parent[Int(run)] != run {
            parent[Int(run)] = parent[Int(parent[Int(run)])]
            run = parent[Int(run)]
        }
        return run
    }

    mutating func join(_ a: Int32, _ b: Int32) {
        let rootA = root(a)
        let rootB = root(b)
        if rootA != rootB {
            parent[Int(max(rootA, rootB))] = min(rootA, rootB)
        }
    }
}

// MARK: - Minimum-area rectangle

/// Convex hull by Andrew's monotone chain, without collinear points.
private func convexHull(_ points: [PixelPoint]) -> [Point] {
    var p = points
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
func smallestRectangle(around points: [PixelPoint]) -> Bar? {
    let hull = convexHull(points)
    var best: (area: Float, along: Point, minU: Float, maxU: Float, minN: Float, maxN: Float)?
    for i in hull.indices {
        let edge = hull[(i + 1) % hull.count] - hull[i]
        guard edge != .zero else { continue }
        let along = simd_normalize(edge)
        let across = along.turnedClockwise
        var minU = Float.greatestFiniteMagnitude
        var maxU = -Float.greatestFiniteMagnitude
        var minN = Float.greatestFiniteMagnitude
        var maxN = -Float.greatestFiniteMagnitude
        for q in hull {
            let u = simd_dot(q, along)
            let n = simd_dot(q, across)
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
    let extentAlong = best.maxU - best.minU
    let extentAcross = best.maxN - best.minN
    return extentAlong >= extentAcross
        ? Bar(center: center, axis: best.along, length: extentAlong, width: extentAcross)
        : Bar(center: center, axis: across, length: extentAcross, width: extentAlong)
}
