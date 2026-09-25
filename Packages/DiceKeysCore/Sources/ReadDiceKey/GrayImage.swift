//
//  GrayImage.swift
//  ReadDiceKey
//
//  An 8-bit grayscale plane and the handful of OpenCV image operations the scanner
//  uses on it, each written to produce the same bytes as the OpenCV routine it replaces:
//
//    cvtColor(RGBA2GRAY)          -> GrayImage(rgba:width:height:)
//    medianBlur(ksize 3)          -> medianBlur3()
//    `gray >= t`                  -> thresholdAtLeast(_:)
//    threshold(THRESH_BINARY)     -> thresholdBinary(_:)
//    Canny(253, 255, aperture 5)  -> canny5(lowThreshold:highThreshold:)
//    dilate(3x3, 1 iteration)     -> dilate3()
//    getRotationMatrix2D+warpAffine (graphics/rotate.h copyRotatedRectangle)
//                                 -> copyRotatedRectangle(center:angleInDegrees:width:height:)
//
//  All loops run over unsafe buffer pointers so a 1080x1080 frame stays cheap.
//

import Foundation

struct GrayImage: Sendable {
    let width: Int
    let height: Int
    var pixels: [UInt8]

    init(width: Int, height: Int) {
        self.width = max(0, width)
        self.height = max(0, height)
        pixels = [UInt8](repeating: 0, count: self.width * self.height)
    }

    init(width: Int, height: Int, pixels: [UInt8]) {
        precondition(pixels.count == width * height)
        self.width = width
        self.height = height
        self.pixels = pixels
    }

    /// Converts tightly packed RGBA bytes to gray with OpenCV's fixed-point luma
    /// (`COLOR_RGBA2GRAY`: R * 4899 + G * 9617 + B * 1868, rounded, over 2^14).
    init(rgba: UnsafeRawBufferPointer, width: Int, height: Int) {
        self.init(width: width, height: height)
        let count = self.width * self.height
        guard rgba.count >= count * 4, let base = rgba.baseAddress?.assumingMemoryBound(to: UInt8.self) else { return }
        pixels.withUnsafeMutableBufferPointer { out in
            var src = 0
            for i in 0..<count {
                let r: Int = Int(base[src]) * 4899
                let g: Int = Int(base[src + 1]) * 9617
                let b: Int = Int(base[src + 2]) * 1868
                let sum: Int = r + g + b + 8192
                out[i] = UInt8(truncatingIfNeeded: sum >> 14)
                src += 4
            }
        }
    }

    @inline(__always)
    subscript(x: Int, y: Int) -> UInt8 {
        pixels[y * width + x]
    }

    // MARK: medianBlur(3)

    /// `cv::medianBlur(src, dst, 3)`: 3x3 median with replicated borders.
    func medianBlur3() -> GrayImage {
        var out = GrayImage(width: width, height: height)
        let w = width, h = height
        guard w > 0 && h > 0 else { return out }
        pixels.withUnsafeBufferPointer { srcBuf in
            out.pixels.withUnsafeMutableBufferPointer { dstBuf in
                guard let src = srcBuf.baseAddress, let dst = dstBuf.baseAddress else { return }
                for y in 0..<h {
                    let r0 = src + max(y - 1, 0) * w
                    let r1 = src + y * w
                    let r2 = src + min(y + 1, h - 1) * w
                    let d = dst + y * w
                    if w == 1 {
                        d[0] = median9(r0[0], r0[0], r0[0], r1[0], r1[0], r1[0], r2[0], r2[0], r2[0])
                        continue
                    }
                    d[0] = median9(r0[0], r0[0], r0[1], r1[0], r1[0], r1[1], r2[0], r2[0], r2[1])
                    var x = 1
                    while x < w - 1 {
                        d[x] = median9(
                            r0[x - 1], r0[x], r0[x + 1],
                            r1[x - 1], r1[x], r1[x + 1],
                            r2[x - 1], r2[x], r2[x + 1]
                        )
                        x += 1
                    }
                    d[w - 1] = median9(r0[w - 2], r0[w - 1], r0[w - 1], r1[w - 2], r1[w - 1], r1[w - 1], r2[w - 2], r2[w - 1], r2[w - 1])
                }
            }
        }
        return out
    }

    // MARK: thresholds

    /// `gray >= threshold`: 255 where the pixel is at least `threshold`, else 0.
    func thresholdAtLeast(_ threshold: Int) -> GrayImage {
        var out = GrayImage(width: width, height: height)
        let t = threshold
        pixels.withUnsafeBufferPointer { src in
            out.pixels.withUnsafeMutableBufferPointer { dst in
                for i in 0..<src.count {
                    dst[i] = Int(src[i]) >= t ? 255 : 0
                }
            }
        }
        return out
    }

    /// `cv::threshold(src, dst, t, 255, THRESH_BINARY)`: 255 where the pixel is above `t`.
    func thresholdBinary(_ threshold: Int) -> GrayImage {
        var out = GrayImage(width: width, height: height)
        let t = threshold
        pixels.withUnsafeBufferPointer { src in
            out.pixels.withUnsafeMutableBufferPointer { dst in
                for i in 0..<src.count {
                    dst[i] = Int(src[i]) > t ? 255 : 0
                }
            }
        }
        return out
    }

    // MARK: dilate

    /// `cv::dilate(src, dst, Mat(), Point(-1, -1))`: 3x3 maximum, one iteration; pixels
    /// outside the image do not take part. Done as a horizontal then a vertical 3-max.
    func dilate3() -> GrayImage {
        var out = GrayImage(width: width, height: height)
        let w = width, h = height
        guard w > 0 && h > 0 else { return out }
        var horizontal = [UInt8](repeating: 0, count: w * h)
        pixels.withUnsafeBufferPointer { srcBuf in
            horizontal.withUnsafeMutableBufferPointer { tmpBuf in
                guard let src = srcBuf.baseAddress, let tmp = tmpBuf.baseAddress else { return }
                for y in 0..<h {
                    let s = src + y * w
                    let t = tmp + y * w
                    if w == 1 {
                        t[0] = s[0]
                        continue
                    }
                    t[0] = max(s[0], s[1])
                    var x = 1
                    while x < w - 1 {
                        t[x] = max(s[x - 1], max(s[x], s[x + 1]))
                        x += 1
                    }
                    t[w - 1] = max(s[w - 2], s[w - 1])
                }
            }
        }
        horizontal.withUnsafeBufferPointer { tmpBuf in
            out.pixels.withUnsafeMutableBufferPointer { dstBuf in
                guard let tmp = tmpBuf.baseAddress, let dst = dstBuf.baseAddress else { return }
                for y in 0..<h {
                    let above = tmp + max(y - 1, 0) * w
                    let row = tmp + y * w
                    let below = tmp + min(y + 1, h - 1) * w
                    let d = dst + y * w
                    for x in 0..<w {
                        d[x] = max(above[x], max(row[x], below[x]))
                    }
                }
            }
        }
        return out
    }

    // MARK: Canny

    /// `cv::Canny(src, dst, low, high, apertureSize: 5)` with the default L1 gradient, as
    /// OpenCV 4 computes it: a 5x5 Sobel (replicated border), |dx| + |dy| magnitudes,
    /// non-maximum suppression in four sectors, then hysteresis over 8-neighbours.
    func canny5(lowThreshold: Double, highThreshold: Double) -> GrayImage {
        let w = width, h = height
        var out = GrayImage(width: width, height: height)
        guard w > 0 && h > 0 else { return out }
        var low = cvFloor(lowThreshold)
        var high = cvFloor(highThreshold)
        if low > high { swap(&low, &high) }

        // Separable Sobel, aperture 5: smoothing [1 4 6 4 1], derivative [-1 -2 0 2 1].
        // Horizontal pass: smoothed-along-x (at most 16 * 255) and differentiated-along-x
        // (at most 3 * 255) both fit Int16; so do the final dx and dy (at most 48 * 255).
        let count = w * h
        // Planes that every pass overwrites completely are left uninitialised.
        var smoothX = [Int16](unsafeUninitializedCapacity: count) { _, n in n = count }
        var derivX = [Int16](unsafeUninitializedCapacity: count) { _, n in n = count }
        pixels.withUnsafeBufferPointer { srcBuf in
            smoothX.withUnsafeMutableBufferPointer { sxBuf in
                derivX.withUnsafeMutableBufferPointer { dxBuf in
                    guard let src = srcBuf.baseAddress, let sxAll = sxBuf.baseAddress, let dxAll = dxBuf.baseAddress else { return }
                    for y in 0..<h {
                        let s = src + y * w
                        let sx = sxAll + y * w
                        let dxp = dxAll + y * w
                        @inline(__always) func tap(_ x: Int) -> Int32 { Int32(s[min(max(x, 0), w - 1)]) }
                        var x = 0
                        // Edges with clamping, interior without.
                        while x < w {
                            let vm2: Int32, vm1: Int32, v0: Int32, vp1: Int32, vp2: Int32
                            if x >= 2 && x + 2 < w {
                                vm2 = Int32(s[x - 2]); vm1 = Int32(s[x - 1]); v0 = Int32(s[x]); vp1 = Int32(s[x + 1]); vp2 = Int32(s[x + 2])
                            } else {
                                vm2 = tap(x - 2); vm1 = tap(x - 1); v0 = tap(x); vp1 = tap(x + 1); vp2 = tap(x + 2)
                            }
                            sx[x] = Int16(truncatingIfNeeded: vm2 + 4 * vm1 + 6 * v0 + 4 * vp1 + vp2)
                            dxp[x] = Int16(truncatingIfNeeded: -vm2 - 2 * vm1 + 2 * vp1 + vp2)
                            x += 1
                        }
                    }
                }
            }
        }
        // Vertical pass, fused with the L1 magnitude, which goes into a plane with a zero
        // border of one pixel on every side. |dx| is at most 48 * 255 and |dy| at most
        // 96 * 255, so their sum (at most 36720) needs UInt16.
        let mapStep = w + 2
        let mapCount = mapStep * (h + 2)
        var dx = [Int16](unsafeUninitializedCapacity: count) { _, n in n = count }
        var dy = [Int16](unsafeUninitializedCapacity: count) { _, n in n = count }
        var mag = [UInt16](repeating: 0, count: mapCount)
        smoothX.withUnsafeBufferPointer { sxBuf in
            derivX.withUnsafeBufferPointer { dxBuf in
                dx.withUnsafeMutableBufferPointer { dxoBuf in
                    dy.withUnsafeMutableBufferPointer { dyoBuf in
                        mag.withUnsafeMutableBufferPointer { magBuf in
                            guard let sx = sxBuf.baseAddress, let dxp = dxBuf.baseAddress,
                                  let dxo = dxoBuf.baseAddress, let dyo = dyoBuf.baseAddress,
                                  let magAll = magBuf.baseAddress else { return }
                            for y in 0..<h {
                                let ym2 = max(y - 2, 0) * w
                                let ym1 = max(y - 1, 0) * w
                                let y0 = y * w
                                let yp1 = min(y + 1, h - 1) * w
                                let yp2 = min(y + 2, h - 1) * w
                                let a2 = dxp + ym2, a1 = dxp + ym1, a0 = dxp + y0, b1 = dxp + yp1, b2 = dxp + yp2
                                let c2 = sx + ym2, c1 = sx + ym1, e1 = sx + yp1, e2 = sx + yp2
                                let ox = dxo + y0, oy = dyo + y0
                                let m = magAll + (y + 1) * mapStep + 1
                                for x in 0..<w {
                                    let gx = Int32(a2[x]) + 4 * Int32(a1[x]) + 6 * Int32(a0[x]) + 4 * Int32(b1[x]) + Int32(b2[x])
                                    let gy = -Int32(c2[x]) - 2 * Int32(c1[x]) + 2 * Int32(e1[x]) + Int32(e2[x])
                                    ox[x] = Int16(truncatingIfNeeded: gx)
                                    oy[x] = Int16(truncatingIfNeeded: gy)
                                    m[x] = UInt16(abs(gx) + abs(gy))
                                }
                            }
                        }
                    }
                }
            }
        }

        // 0 = weak candidate, 1 = not an edge, 2 = edge; the border is 1.
        var map = [UInt8](repeating: 1, count: mapCount)
        var stack = [Int]()
        stack.reserveCapacity(4096)
        let cannyShift = 15
        let tg22 = Int32(0.4142135623730950488016887242097 * Double(1 << cannyShift) + 0.5)

        dx.withUnsafeBufferPointer { dxp in
            dy.withUnsafeBufferPointer { dyp in
                mag.withUnsafeBufferPointer { magp in
                    map.withUnsafeMutableBufferPointer { mapp in
                        for y in 0..<h {
                            let magRow = (y + 1) * mapStep + 1
                            let magAbove = magRow - mapStep
                            let magBelow = magRow + mapStep
                            let gradRow = y * w
                            for x in 0..<w {
                                let m = Int32(magp[magRow + x])
                                if m > Int32(low) {
                                    let xs = Int32(dxp[gradRow + x])
                                    let ys = Int32(dyp[gradRow + x])
                                    let ax = abs(xs)
                                    let ay = abs(ys) << Int32(cannyShift)
                                    let tg22x = ax &* tg22
                                    var isMax = false
                                    if ay < tg22x {
                                        isMax = m > Int32(magp[magRow + x - 1]) && m >= Int32(magp[magRow + x + 1])
                                    } else {
                                        let tg67x = tg22x &+ (ax << Int32(1 + cannyShift))
                                        if ay > tg67x {
                                            isMax = m > Int32(magp[magAbove + x]) && m >= Int32(magp[magBelow + x])
                                        } else {
                                            let s = (xs ^ ys) < 0 ? -1 : 1
                                            isMax = m > Int32(magp[magAbove + x - s]) && m > Int32(magp[magBelow + x + s])
                                        }
                                    }
                                    if isMax {
                                        if m > Int32(high) {
                                            mapp[magRow + x] = 2
                                            stack.append(magRow + x)
                                        } else {
                                            mapp[magRow + x] = 0
                                        }
                                        continue
                                    }
                                }
                                mapp[magRow + x] = 1
                            }
                        }
                        // Hysteresis: grow the strong edges into adjacent weak candidates.
                        let offsets = [-mapStep - 1, -mapStep, -mapStep + 1, -1, 1, mapStep - 1, mapStep, mapStep + 1]
                        while let i = stack.popLast() {
                            for off in offsets {
                                let j = i + off
                                if mapp[j] == 0 {
                                    mapp[j] = 2
                                    stack.append(j)
                                }
                            }
                        }
                    }
                }
            }
        }
        map.withUnsafeBufferPointer { mapp in
            out.pixels.withUnsafeMutableBufferPointer { dst in
                for y in 0..<h {
                    let src = (y + 1) * mapStep + 1
                    let row = y * w
                    for x in 0..<w {
                        dst[row + x] = mapp[src + x] == 2 ? 255 : 0
                    }
                }
            }
        }
        return out
    }

    // MARK: warpAffine crop (graphics/rotate.h copyRotatedRectangle)

    /// Copies a `width` x `height` rectangle centred on `center` after rotating the image by
    /// `angleInDegrees` (counter-clockwise for positive angles), exactly as
    /// `copyRotatedRectangle` does with `getRotationMatrix2D` + `warpAffine`: bilinear
    /// interpolation on OpenCV's 1/32-pixel fixed-point grid, black outside the image.
    func copyRotatedRectangle(center: Point2f, angleInDegrees: Float, width dstWidth: Int, height dstHeight: Int) -> GrayImage {
        var out = GrayImage(width: dstWidth, height: dstHeight)
        guard dstWidth > 0 && dstHeight > 0 && width > 0 && height > 0 else { return out }
        // getRotationMatrix2D(center, angle, 1.0)
        let angle = Double(angleInDegrees)
        let alpha = cos(angle * Double.pi / 180)
        let beta = sin(angle * Double.pi / 180)
        var m0 = alpha
        var m1 = beta
        var m2 = (1 - alpha) * Double(center.x) - beta * Double(center.y)
        var m3 = -beta
        var m4 = alpha
        var m5 = beta * Double(center.x) + (1 - alpha) * Double(center.y)
        // Shift so the source center lands on the destination center.
        m2 += Double(dstWidth) / 2.0 - Double(center.x)
        m5 += Double(dstHeight) / 2.0 - Double(center.y)
        // warpAffine inverts the matrix (no WARP_INVERSE_MAP flag).
        var d = m0 * m4 - m1 * m3
        d = d != 0 ? 1.0 / d : 0
        let a11 = m4 * d
        let a22 = m0 * d
        m0 = a11
        m1 *= -d
        m3 *= -d
        m4 = a22
        let b1 = -m0 * m2 - m1 * m5
        let b2 = -m3 * m2 - m4 * m5
        m2 = b1
        m5 = b2

        let abBits = 10
        let abScale = Double(1 << abBits)
        let interBits = 5
        let interTabSize = 32
        let roundDelta = (1 << abBits) / interTabSize / 2
        let sw = width, sh = height
        var adelta = [Int](repeating: 0, count: dstWidth)
        var bdelta = [Int](repeating: 0, count: dstWidth)
        for x in 0..<dstWidth {
            adelta[x] = cvRound(m0 * Double(x) * abScale)
            bdelta[x] = cvRound(m3 * Double(x) * abScale)
        }
        pixels.withUnsafeBufferPointer { src in
            out.pixels.withUnsafeMutableBufferPointer { dst in
                for y in 0..<dstHeight {
                    let x0 = cvRound((m1 * Double(y) + m2) * abScale) + roundDelta
                    let y0 = cvRound((m4 * Double(y) + m5) * abScale) + roundDelta
                    let dstRow = y * dstWidth
                    for x in 0..<dstWidth {
                        let xFixed = (x0 + adelta[x]) >> (abBits - interBits)
                        let yFixed = (y0 + bdelta[x]) >> (abBits - interBits)
                        let sx = xFixed >> interBits
                        let sy = yFixed >> interBits
                        let fx = xFixed & (interTabSize - 1)
                        let fy = yFixed & (interTabSize - 1)
                        var result = 0
                        if !(sx >= sw || sx + 1 < 0 || sy >= sh || sy + 1 < 0) {
                            let v0 = (sx >= 0 && sy >= 0) ? Int(src[sy * sw + sx]) : 0
                            let v1 = (sx + 1 < sw && sy >= 0) ? Int(src[sy * sw + sx + 1]) : 0
                            let v2 = (sx >= 0 && sy + 1 < sh) ? Int(src[(sy + 1) * sw + sx]) : 0
                            let v3 = (sx + 1 < sw && sy + 1 < sh) ? Int(src[(sy + 1) * sw + sx + 1]) : 0
                            // OpenCV's bilinear table entries are (1-fy)(1-fx) etc. scaled by 2^15,
                            // which for a 32-step grid is an exact multiple of 32.
                            let w0 = (32 - fy) * (32 - fx) * 32
                            let w1 = (32 - fy) * fx * 32
                            let w2 = fy * (32 - fx) * 32
                            let w3 = fy * fx * 32
                            let v = v0 * w0 + v1 * w1 + v2 * w2 + v3 * w3
                            result = (v + (1 << 14)) >> 15
                            result = min(255, max(0, result))
                        }
                        dst[dstRow + x] = UInt8(result)
                    }
                }
            }
        }
        return out
    }
}

/// Median of nine bytes by a partial sorting network (the same result as sorting).
@inline(__always)
private func median9(
    _ a0: UInt8, _ a1: UInt8, _ a2: UInt8,
    _ a3: UInt8, _ a4: UInt8, _ a5: UInt8,
    _ a6: UInt8, _ a7: UInt8, _ a8: UInt8
) -> UInt8 {
    var p0 = a0, p1 = a1, p2 = a2, p3 = a3, p4 = a4, p5 = a5, p6 = a6, p7 = a7, p8 = a8
    @inline(__always) func sw(_ a: inout UInt8, _ b: inout UInt8) {
        if a > b { let t = a; a = b; b = t }
    }
    sw(&p1, &p2); sw(&p4, &p5); sw(&p7, &p8)
    sw(&p0, &p1); sw(&p3, &p4); sw(&p6, &p7)
    sw(&p1, &p2); sw(&p4, &p5); sw(&p7, &p8)
    sw(&p0, &p3); sw(&p5, &p8); sw(&p4, &p7)
    sw(&p3, &p6); sw(&p1, &p4); sw(&p2, &p5)
    sw(&p4, &p7); sw(&p4, &p2); sw(&p6, &p4)
    sw(&p4, &p2)
    return p4
}
