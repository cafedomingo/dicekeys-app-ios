//
//  DiceKeyReader.swift
//  ReadDiceKey
//
//  The frame loop of lib-read-dicekey/read-dicekey.{hpp,cpp} (`DiceKeyImageProcessor`):
//  accumulate reads across frames, merge them, and stop when the key is read without
//  error or the correctable errors have not improved for four seconds. Also the JSON
//  output (`DiceKey<FaceRead>::toJson`, `FaceRead::toJson`, `Undoverline::toJson`) and the
//  overlay renderer (visualize-read-results.cpp, write-face-characters.cpp,
//  graphics/draw-rotated-rect.cpp).
//

import Foundation

/// read-dicekey.cpp line 15: errors of at most this size are treated as correctable.
let maxCorrectableError: UInt = 2
/// read-dicekey.cpp line 16: how long to keep scanning in the hope of correcting them.
let millisecondsToTryToRemoveCorrectableErrors = 4000

/// The scanner state: the port of `DiceKeyImageProcessor`. A value type; `DiceKeyScanner`
/// wraps one in the class the app already uses.
struct DiceKeyReader: Sendable {
    private var initialized = false
    private var angleInRadiansNonCanonicalForm: Float = 0
    private var pixelsPerFaceEdgeWidth: Float = 0
    private var whenFirstRead: ContinuousClock.Instant?
    private var whenLastImproved: ContinuousClock.Instant?
    private var whenLastRead: ContinuousClock.Instant?
    /// The DiceKey read so far, with the errors still to resolve.
    private(set) var diceKey = DiceKeyRead()
    private var previousDiceKey = DiceKeyRead()
    /// True once the termination condition of the scanning loop was reached.
    private(set) var terminate = false

    init() {}

    // MARK: Frame processing

    /// `DiceKeyImageProcessor::processRGBAImage`: converts to gray and processes.
    ///
    /// The C++ also copied a colour crop of every face read with errors into `imageData` for
    /// `getImageOfFace`, which the C ABI never exposed; that is not ported.
    mutating func processRGBA(_ rgba: UnsafeRawBufferPointer, width: Int, height: Int) -> Bool {
        let gray = GrayImage(rgba: rgba, width: width, height: height)
        return process(gray: gray)
    }

    /// `DiceKeyImageProcessor::processImage`.
    mutating func process(gray: GrayImage) -> Bool {
        let facesRead = readFaces(gray)

        let now = ContinuousClock.now
        whenLastRead = now
        if !initialized {
            whenFirstRead = now
            whenLastImproved = now
            initialized = true
        }

        if facesRead.success && facesRead.faces.count == numberOfFaces {
            angleInRadiansNonCanonicalForm = facesRead.angleInRadiansNonCanonicalForm
            pixelsPerFaceEdgeWidth = facesRead.pixelsPerFaceEdgeWidth

            if diceKey.isInitialized {
                previousDiceKey = diceKey
            }
            if previousDiceKey.isInitialized {
                // Merge the previous read into this one: it may have read something this one missed.
                diceKey = DiceKeyRead(faces: facesRead.faces).mergePrevious(previousDiceKey)
                // Kept exactly as read-dicekey.cpp lines 59-62 have it (the comparison reads
                // as inverted; upstream behaviour is what the app has always shipped).
                if diceKey.totalError > previousDiceKey.totalError {
                    whenLastImproved = now
                }
            } else {
                diceKey = DiceKeyRead(faces: facesRead.faces)
                whenLastImproved = now
            }
        } else {
            diceKey = DiceKeyRead()
        }

        // Stop when the scan is error free, or when only correctable errors remain and the
        // time budget for scanning them away has run out.
        // VERIFY: whole milliseconds compared `> 4000`, as duration_cast<milliseconds>(...).count()
        // did; check the four-second fallback on device with a key carrying a persistent bit error.
        let millisecondsSinceImprovement: Int
        if let lastRead = whenLastRead, let lastImproved = whenLastImproved {
            millisecondsSinceImprovement = Int(((lastRead - lastImproved) / .milliseconds(1)).rounded(.towardZero))
        } else {
            millisecondsSinceImprovement = 0
        }
        terminate = diceKey.totalError == 0
            || (diceKey.maxError <= maxCorrectableError && millisecondsSinceImprovement > millisecondsToTryToRemoveCorrectableErrors)
        return terminate
    }

    var isFinished: Bool { terminate }

    // MARK: JSON (dicekey.hpp toJson, face-read.cpp toJson, undoverline.cpp toJson)

    /// The faces read as a JSON array of 25 objects, or "null" before any full read.
    var jsonDiceKeyRead: String {
        if !diceKey.isInitialized {
            return "null"
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(diceKey.faces.map(FaceReadJSON.init)) else {
            return "null"
        }
        return String(decoding: data, as: UTF8.self)
    }

    // MARK: Overlay (read-dicekey.cpp renderAugmentationOverlay / augmentRGBAImage)

    /// Clears the buffer to transparent and draws what has been read.
    func renderAugmentationOverlay(_ rgba: UnsafeMutableRawBufferPointer, width: Int, height: Int) {
        let count = width * height * 4
        guard count > 0, rgba.count >= count else { return }
        let bytes = rgba.bindMemory(to: UInt8.self)
        for i in 0..<count {
            bytes[i] = 0
        }
        augmentRGBAImage(rgba, width: width, height: height)
    }

    /// Draws what has been read over an existing RGBA frame.
    func augmentRGBAImage(_ rgba: UnsafeMutableRawBufferPointer, width: Int, height: Int) {
        guard diceKey.isInitialized && diceKey.faces.count == numberOfFaces else { return }
        guard width > 0, height > 0, rgba.count >= width * height * 4 else { return }
        let bytes = rgba.bindMemory(to: UInt8.self)
        var canvas = RGBACanvas(pixels: bytes, width: width, height: height)
        visualizeReadResults(&canvas, faces: diceKey.faces, angleInRadiansNonCanonicalForm: angleInRadiansNonCanonicalForm, pixelsPerFaceEdgeWidth: pixelsPerFaceEdgeWidth)
    }
}

// MARK: - JSON shapes

private func finiteOrZero(_ v: Float) -> Float { v.isFinite ? v : 0 }

private struct PointJSON: Encodable {
    let x: Float
    let y: Float

    init(_ p: Point2f) {
        x = finiteOrZero(p.x)
        y = finiteOrZero(p.y)
    }
}

private struct LineJSON: Encodable {
    let start: PointJSON
    let end: PointJSON

    init(_ line: Line) {
        start = PointJSON(line.start)
        end = PointJSON(line.end)
    }
}

private struct UndoverlineJSON: Encodable {
    let code: UInt8
    let line: LineJSON

    /// `Undoverline::toJson` yields null unless the line was found and decoded.
    init?(_ u: Undoverline) {
        guard u.found && u.determinedIfUnderlineOrOverline else { return nil }
        code = u.letterDigitEncoding
        line = LineJSON(u.line)
    }
}

/// `FaceRead::toJson`. Keys match the C++ (`JsonKeys::FaceRead`). Absent undoverlines are
/// encoded as JSON null, as the C++ does. The one deliberate difference: an unknown
/// orientation is null rather than the string "?", because the app decodes the field as an
/// optional t/r/b/l enum and "?" would fail the whole decode.
private struct FaceReadJSON: Encodable {
    let underline: UndoverlineJSON?
    let overline: UndoverlineJSON?
    let center: PointJSON
    let orientationAsLowercaseLetterTrbl: String?
    let ocrLetterCharsFromMostToLeastLikely: String
    let ocrDigitCharsFromMostToLeastLikely: String

    init(_ face: FaceRead) {
        underline = UndoverlineJSON(face.underline)
        overline = UndoverlineJSON(face.overline)
        center = PointJSON(face.center())
        let orientation = face.orientationAsLowercaseLetterTrbl
        orientationAsLowercaseLetterTrbl = orientation == questionMarkByte ? nil : String(decoding: [orientation], as: UTF8.self)
        ocrLetterCharsFromMostToLeastLikely = String(decoding: face.ocrLetterFromMostToLeastLikely, as: UTF8.self)
        ocrDigitCharsFromMostToLeastLikely = String(decoding: face.ocrDigitFromMostToLeastLikely, as: UTF8.self)
    }

    enum CodingKeys: String, CodingKey {
        case underline, overline, center, orientationAsLowercaseLetterTrbl
        case ocrLetterCharsFromMostToLeastLikely, ocrDigitCharsFromMostToLeastLikely
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        if let underline { try c.encode(underline, forKey: .underline) } else { try c.encodeNil(forKey: .underline) }
        if let overline { try c.encode(overline, forKey: .overline) } else { try c.encodeNil(forKey: .overline) }
        try c.encode(center, forKey: .center)
        if let o = orientationAsLowercaseLetterTrbl { try c.encode(o, forKey: .orientationAsLowercaseLetterTrbl) } else { try c.encodeNil(forKey: .orientationAsLowercaseLetterTrbl) }
        try c.encode(ocrLetterCharsFromMostToLeastLikely, forKey: .ocrLetterCharsFromMostToLeastLikely)
        try c.encode(ocrDigitCharsFromMostToLeastLikely, forKey: .ocrDigitCharsFromMostToLeastLikely)
    }
}

// MARK: - Overlay drawing

/// graphics/color.h `Color`, written into RGBA buffers as (r, g, b, 255).
struct OverlayColor: Sendable {
    let r: UInt8
    let g: UInt8
    let b: UInt8
}

/// visualize-read-results.h: the three result colours.
let colorNoErrorGreen = OverlayColor(r: 0, g: 192, b: 0)
let colorSmallErrorOrange = OverlayColor(r: 192, g: 96, b: 0)
let colorBigErrorRed = OverlayColor(r: 128, g: 0, b: 0)

func errorMagnitudeToColor(_ errorMagnitude: UInt) -> OverlayColor {
    errorMagnitude == 0 ? colorNoErrorGreen : (errorMagnitude <= 3 ? colorSmallErrorOrange : colorBigErrorRed)
}

/// A view over a tightly packed RGBA buffer with the few drawing primitives the overlay needs.
struct RGBACanvas {
    let pixels: UnsafeMutableBufferPointer<UInt8>
    let width: Int
    let height: Int

    @inline(__always)
    mutating func setPixel(_ x: Int, _ y: Int, _ color: OverlayColor) {
        guard x >= 0, y >= 0, x < width, y < height else { return }
        let i = (y * width + x) * 4
        pixels[i] = color.r
        pixels[i + 1] = color.g
        pixels[i + 2] = color.b
        pixels[i + 3] = 255
    }

    /// An 8-connected Bresenham line with a square brush of the given thickness
    /// (`cv::line` with LINE_8; the exact brush shape of OpenCV's thick lines is cosmetic).
    mutating func line(from a: Point2i, to b: Point2i, color: OverlayColor, thickness: Int) {
        let dx = abs(Int(b.x) - Int(a.x)), sx = a.x < b.x ? 1 : -1
        let dy = -abs(Int(b.y) - Int(a.y)), sy = a.y < b.y ? 1 : -1
        var err = dx + dy
        var x = Int(a.x), y = Int(a.y)
        let r = max(0, thickness / 2)
        // Guard against absurd coordinates (the loop is linear in the span).
        if dx > 1 << 16 || -dy > 1 << 16 { return }
        while true {
            var oy = -r
            while oy <= r {
                var ox = -r
                while ox <= r {
                    setPixel(x + ox, y + oy, color)
                    ox += 1
                }
                oy += 1
            }
            if x == Int(b.x) && y == Int(b.y) { break }
            let e2 = 2 * err
            if e2 >= dy { err += dy; x += sx }
            if e2 <= dx { err += dx; y += sy }
        }
    }

    /// draw-rotated-rect.cpp `drawRotatedRect`: a closed polyline through the four corners,
    /// each rounded to a pixel as `cv::Point(pointsf[i])` does.
    mutating func drawRotatedRect(_ rrect: RotatedRect, color: OverlayColor, thickness: Int) {
        let corners = rrect.points().map { Point2i(cvRound($0.x), cvRound($0.y)) }
        for i in 0..<4 {
            line(from: corners[i], to: corners[(i + 1) % 4], color: color, thickness: thickness)
        }
    }
}

/// visualize-read-results.cpp `visualizeReadResults`: boxes around faces with errors, boxes
/// around every undoverline (thick and coloured where the error lies), and the letter and
/// digit read drawn over each face.
func visualizeReadResults(_ canvas: inout RGBACanvas, faces: [FaceRead], angleInRadiansNonCanonicalForm: Float, pixelsPerFaceEdgeWidth: Float) {
    let faceSizeInPixels = FaceDimensionsFractional.size * pixelsPerFaceEdgeWidth
    guard faceSizeInPixels.isFinite else { return }
    let thinLineThickness = 1 + Int(faceSizeInPixels / 70)
    let thickLineThickness = 2 * thinLineThickness

    for face in faces {
        let error = face.error()
        let magnitude = UInt(error.magnitude)
        if error.magnitude > 0 {
            canvas.drawRotatedRect(
                RotatedRect(center: face.center(), size: Size2f(faceSizeInPixels, faceSizeInPixels), angle: radiansToDegrees(angleInRadiansNonCanonicalForm)),
                color: errorMagnitudeToColor(magnitude),
                thickness: thickLineThickness
            )
        }
        if face.underline.found {
            let underlineError = (error.location & FaceErrors.Location.underline) != 0
            canvas.drawRotatedRect(face.underline.fromRotatedRect,
                                   color: errorMagnitudeToColor(underlineError ? magnitude : 0),
                                   thickness: underlineError ? thickLineThickness : thinLineThickness)
        }
        if face.overline.found {
            let overlineError = (error.location & FaceErrors.Location.overline) != 0
            canvas.drawRotatedRect(face.overline.fromRotatedRect,
                                   color: errorMagnitudeToColor(overlineError ? magnitude : 0),
                                   thickness: overlineError ? thickLineThickness : thinLineThickness)
        }
        writeFaceCharacters(
            &canvas,
            faceCenter: face.center(),
            angleInRadians: face.inferredAngleInRadians(),
            pixelsPerFaceEdgeWidth: pixelsPerFaceEdgeWidth,
            letter: face.letter,
            digit: face.digit,
            letterColor: errorMagnitudeToColor((error.location & FaceErrors.Location.ocrLetter) != 0 ? magnitude : 0),
            digitColor: errorMagnitudeToColor((error.location & FaceErrors.Location.ocrDigit) != 0 ? magnitude : 0)
        )
    }
}

/// write-face-characters.cpp `writeFaceCharacters`: plots the glyph outlines of the letter
/// and digit, scaled and rotated onto the face. (The C++ bounds check used `||` and could
/// write outside the image; here every pixel is clipped.)
func writeFaceCharacters(
    _ canvas: inout RGBACanvas, faceCenter: Point2f, angleInRadians: Float, pixelsPerFaceEdgeWidth: Float,
    letter: UInt8, digit: UInt8, letterColor: OverlayColor, digitColor: OverlayColor
) {
    let font = GlyphTemplates.shared
    let textHeightDestinationPixels = FaceDimensionsFractional.textRegionHeight * pixelsPerFaceEdgeWidth
    let textWidthDestinationPixels = FaceDimensionsFractional.textRegionWidth * pixelsPerFaceEdgeWidth
    let destinationPixelsBetweenLetterAndDigit = FaceDimensionsFractional.spaceBetweenLetterAndDigit * pixelsPerFaceEdgeWidth
    let charWidthDestinationPixels = (textWidthDestinationPixels - destinationPixelsBetweenLetterAndDigit) / 2
    guard charWidthDestinationPixels > 0, charWidthDestinationPixels.isFinite else { return }

    let outlineWidth = Float(font.outlineCharWidthInPixels)
    let outlineHeight = Float(font.outlineCharHeightInPixels)
    let centerSpaceInOriginPixels = FaceDimensionsFractional.spaceBetweenLetterAndDigit * pixelsPerFaceEdgeWidth * outlineWidth / charWidthDestinationPixels
    let textTopInOriginPixels = -outlineHeight / 2
    let letterLeftInOriginPixels = -(outlineWidth + centerSpaceInOriginPixels / 2)
    let digitLeftInOriginPixels = centerSpaceInOriginPixels / 2

    let deltaXFraction = charWidthDestinationPixels / outlineWidth
    let deltaYFraction = textHeightDestinationPixels / outlineHeight

    let deltaXFromSourceChangeInX = deltaXFraction * cos(-angleInRadians)
    let deltaXFromSourceChangeInY = deltaYFraction * sin(-angleInRadians)
    let deltaYFromSourceChangeInX = deltaXFraction * cos(Float(Double(-angleInRadians) + Double.pi / 2))
    let deltaYFromSourceChangeInY = deltaYFraction * sin(Float(Double(-angleInRadians) + Double.pi / 2))

    let letterTopLeftX = faceCenter.x + letterLeftInOriginPixels * deltaXFromSourceChangeInX + textTopInOriginPixels * deltaXFromSourceChangeInY
    let letterTopLeftY = faceCenter.y + letterLeftInOriginPixels * deltaYFromSourceChangeInX + textTopInOriginPixels * deltaYFromSourceChangeInY
    let digitTopLeftX = faceCenter.x + digitLeftInOriginPixels * deltaXFromSourceChangeInX + textTopInOriginPixels * deltaXFromSourceChangeInY
    let digitTopLeftY = faceCenter.y + digitLeftInOriginPixels * deltaYFromSourceChangeInX + textTopInOriginPixels * deltaYFromSourceChangeInY

    func plot(runs: [(y: Int, xStart: Int, xEnd: Int)], topLeftX: Float, topLeftY: Float, color: OverlayColor) {
        for run in runs {
            let py = Float(run.y)
            var px = run.xStart
            while px <= run.xEnd {
                let fx = Float(px)
                let x = cRoundToInt(topLeftX + deltaXFromSourceChangeInX * fx + deltaXFromSourceChangeInY * py)
                let y = cRoundToInt(topLeftY + deltaYFromSourceChangeInX * fx + deltaYFromSourceChangeInY * py)
                canvas.setPixel(x, y, color)
                px += 1
            }
        }
    }
    if let runs = font.outlineRuns(for: letter) {
        plot(runs: runs, topLeftX: letterTopLeftX, topLeftY: letterTopLeftY, color: letterColor)
    }
    if let runs = font.outlineRuns(for: digit) {
        plot(runs: runs, topLeftX: digitTopLeftX, topLeftY: digitTopLeftY, color: digitColor)
    }
}
