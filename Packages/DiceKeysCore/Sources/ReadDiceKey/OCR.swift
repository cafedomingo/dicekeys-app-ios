//
//  OCR.swift
//  ReadDiceKey
//
//  Template-correlation OCR of the letter and digit on a face:
//  lib-read-dicekey/simple-ocr.cpp (findClosestMatchingCharacter) and
//  read-face-characters.cpp (cropping the text region and splitting it in two). The glyph
//  model comes from OcrFontTables.swift, generated from the C++ font data.
//

import Foundation

/// The Inconsolata Bold glyph model: penalty tables for the OCR and filled outlines for
/// drawing (font.h / ocr-font.h `OcrFont`, decoded once from `InconsolataOCRFontData`).
struct GlyphTemplates: Sendable {
    let ocrCharWidthInPixels: Int
    let ocrCharHeightInPixels: Int
    let outlineCharWidthInPixels: Int
    let outlineCharHeightInPixels: Int
    /// ASCII bytes of the letters, in table order.
    let letterCharacters: [UInt8]
    let digitCharacters: [UInt8]
    /// `[row][column][characterIndex]`: high nibble is the penalty when the image pixel is
    /// white, low nibble when it is black.
    let letterPenalties: [UInt8]
    let digitPenalties: [UInt8]
    /// Filled pixels of each glyph at outline resolution, letters then digits, as (y, xStart, xEnd) runs.
    let outlineRuns: [[(y: Int, xStart: Int, xEnd: Int)]]

    static let shared = GlyphTemplates()

    private init() {
        ocrCharWidthInPixels = InconsolataOCRFontData.ocrCharWidthInPixels
        ocrCharHeightInPixels = InconsolataOCRFontData.ocrCharHeightInPixels
        outlineCharWidthInPixels = InconsolataOCRFontData.outlineCharWidthInPixels
        outlineCharHeightInPixels = InconsolataOCRFontData.outlineCharHeightInPixels
        letterCharacters = Array(InconsolataOCRFontData.letterCharacters.utf8)
        digitCharacters = Array(InconsolataOCRFontData.digitCharacters.utf8)
        letterPenalties = GlyphTemplates.decodeBase64(InconsolataOCRFontData.letterPenaltiesBase64)
        digitPenalties = GlyphTemplates.decodeBase64(InconsolataOCRFontData.digitPenaltiesBase64)
        outlineRuns = InconsolataOCRFontData.outlineRunsBase64.map { encoded in
            let bytes = GlyphTemplates.decodeBase64(encoded)
            var runs: [(y: Int, xStart: Int, xEnd: Int)] = []
            runs.reserveCapacity(bytes.count / 6)
            var i = 0
            while i + 6 <= bytes.count {
                let y = Int(bytes[i]) | (Int(bytes[i + 1]) << 8)
                let x0 = Int(bytes[i + 2]) | (Int(bytes[i + 3]) << 8)
                let x1 = Int(bytes[i + 4]) | (Int(bytes[i + 5]) << 8)
                runs.append((y, x0, x1))
                i += 6
            }
            return runs
        }
        let expectedLetterBytes = ocrCharWidthInPixels * ocrCharHeightInPixels * letterCharacters.count
        let expectedDigitBytes = ocrCharWidthInPixels * ocrCharHeightInPixels * digitCharacters.count
        precondition(letterPenalties.count == expectedLetterBytes, "letter penalty table has \(letterPenalties.count) bytes, expected \(expectedLetterBytes)")
        precondition(digitPenalties.count == expectedDigitBytes, "digit penalty table has \(digitPenalties.count) bytes, expected \(expectedDigitBytes)")
        precondition(outlineRuns.count == letterCharacters.count + digitCharacters.count)
    }

    private static func decodeBase64(_ text: String) -> [UInt8] {
        // The generated literals are wrapped across lines; ignore the newlines.
        guard let data = Data(base64Encoded: text, options: .ignoreUnknownCharacters) else {
            preconditionFailure("OcrFontTables.swift holds invalid base64")
        }
        return [UInt8](data)
    }

    /// Outline runs of a character, or nil if the font has no such glyph.
    func outlineRuns(for character: UInt8) -> [(y: Int, xStart: Int, xEnd: Int)]? {
        if let i = letterCharacters.firstIndex(of: character) {
            return outlineRuns[i]
        }
        if let i = digitCharacters.firstIndex(of: character) {
            return outlineRuns[letterCharacters.count + i]
        }
        return nil
    }
}

/// simple-ocr.h `OcrResultEntry`.
struct OcrResultEntry: Sendable {
    var character: UInt8
    var errorScore: Int
}

/// simple-ocr.h `OcrResult`: every character of the alphabet, lowest error first.
typealias OcrResult = [OcrResultEntry]

/// simple-ocr.cpp `findClosestMatchingCharacter`: for each pixel of the black/white
/// character image, map it to the model raster and add the penalty for its colour to
/// every character; sort by total penalty (a stable sort, keeping table order for ties as
/// `std::sort` did in practice).
func findClosestMatchingCharacter(
    font: GlyphTemplates, characters: [UInt8], penalties: [UInt8],
    image: GrayImage, x0: Int, width imageWidth: Int
) -> OcrResult {
    let imageHeight = image.height
    let numberOfCharactersInAlphabet = characters.count
    var scores = [Int](repeating: 0, count: numberOfCharactersInAlphabet)
    if imageWidth > 0 && imageHeight > 0 {
        let charWidthOverImageWidth = Float(font.ocrCharWidthInPixels) / Float(imageWidth)
        let charHeightOverImageHeight = Float(font.ocrCharHeightInPixels) / Float(imageHeight)
        let penaltyStepX = numberOfCharactersInAlphabet
        let penaltyStepY = penaltyStepX * font.ocrCharWidthInPixels
        penalties.withUnsafeBufferPointer { pen in
            image.pixels.withUnsafeBufferPointer { px in
                scores.withUnsafeMutableBufferPointer { sc in
                    for imageY in 0..<imageHeight {
                        let modelY = min(font.ocrCharHeightInPixels - 1, Int((Float(imageY) + 0.5) * charHeightOverImageHeight))
                        let penaltyRow = modelY * penaltyStepY
                        let pixelRow = imageY * image.width + x0
                        for imageX in 0..<imageWidth {
                            let modelX = min(font.ocrCharWidthInPixels - 1, Int((Float(imageX) + 0.5) * charWidthOverImageWidth))
                            let penaltyBase = penaltyRow + modelX * penaltyStepX
                            let isImagePixelBlack = px[pixelRow + imageX] < 128
                            if isImagePixelBlack {
                                for charIndex in 0..<numberOfCharactersInAlphabet {
                                    sc[charIndex] += Int(pen[penaltyBase + charIndex] & 0xf)
                                }
                            } else {
                                for charIndex in 0..<numberOfCharactersInAlphabet {
                                    sc[charIndex] += Int(pen[penaltyBase + charIndex] >> 4)
                                }
                            }
                        }
                    }
                }
            }
        }
    }
    var result: OcrResult = []
    result.reserveCapacity(numberOfCharactersInAlphabet)
    for i in 0..<numberOfCharactersInAlphabet {
        result.append(OcrResultEntry(character: characters[i], errorScore: scores[i]))
    }
    // VERIFY: std::sort is not stable; ties between characters keep table order here.
    return result.enumerated().sorted { a, b in
        a.element.errorScore < b.element.errorScore || (a.element.errorScore == b.element.errorScore && a.offset < b.offset)
    }.map { $0.element }
}

/// read-face-characters.h `CharactersReadFromFaces`.
struct CharactersReadFromFaces: Sendable {
    let lettersMostLikelyFirst: OcrResult
    let digitsMostLikelyFirst: OcrResult
}

/// read-face-characters.cpp `readCharactersOnFace`: crops the text region of the face
/// (rotated upright), thresholds it, splits it into the letter half and the digit half and
/// runs the OCR on each.
func readCharactersOnFace(
    _ gray: GrayImage, faceCenter: Point2f, angleRadians: Float, pixelsPerFaceEdgeWidth: Float, whiteBlackThreshold: UInt8
) -> CharactersReadFromFaces {
    let degreesToRotateToRemoveAngleOfFace = radiansToDegrees(angleRadians)
    // A non-finite or absurd face size would make the Int conversions below trap where the
    // C++ merely misbehaved; treat it as an unreadable (empty) text region instead.
    guard pixelsPerFaceEdgeWidth.isFinite, pixelsPerFaceEdgeWidth >= 0, pixelsPerFaceEdgeWidth < 65536,
          angleRadians.isFinite, faceCenter.x.isFinite, faceCenter.y.isFinite else {
        let font = GlyphTemplates.shared
        let empty = GrayImage(width: 0, height: 0)
        return CharactersReadFromFaces(
            lettersMostLikelyFirst: findClosestMatchingCharacter(font: font, characters: font.letterCharacters, penalties: font.letterPenalties, image: empty, x0: 0, width: 0),
            digitsMostLikelyFirst: findClosestMatchingCharacter(font: font, characters: font.digitCharacters, penalties: font.digitPenalties, image: empty, x0: 0, width: 0)
        )
    }
    let textHeightPixels = Int((FaceDimensionsFractional.textRegionHeight * pixelsPerFaceEdgeWidth).rounded(.up))
    var textWidthPixels = Int((FaceDimensionsFractional.textRegionWidth * pixelsPerFaceEdgeWidth).rounded(.up))
    // An even width splits cleanly in two at the centre.
    if textWidthPixels % 2 == 1 {
        textWidthPixels += 1
    }
    let textImage = gray.copyRotatedRectangle(center: faceCenter, angleInDegrees: degreesToRotateToRemoveAngleOfFace, width: textWidthPixels, height: textHeightPixels)
    // cv::threshold(textImage, textEdges, whiteBlackThreshold, 255, THRESH_BINARY)
    let textEdges = textImage.thresholdBinary(Int(whiteBlackThreshold))

    let charWidth = Int((Float(textWidthPixels) - (FaceDimensionsFractional.spaceBetweenLetterAndDigit * pixelsPerFaceEdgeWidth).rounded(.toNearestOrAwayFromZero)) / 2)
    let font = GlyphTemplates.shared
    let lettersMostLikelyFirst = findClosestMatchingCharacter(
        font: font, characters: font.letterCharacters, penalties: font.letterPenalties,
        image: textEdges, x0: 0, width: max(0, charWidth)
    )
    let digitsMostLikelyFirst = findClosestMatchingCharacter(
        font: font, characters: font.digitCharacters, penalties: font.digitPenalties,
        image: textEdges, x0: max(0, textWidthPixels - charWidth), width: max(0, min(charWidth, textWidthPixels))
    )
    return CharactersReadFromFaces(lettersMostLikelyFirst: lettersMostLikelyFirst, digitsMostLikelyFirst: digitsMostLikelyFirst)
}
