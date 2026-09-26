//
//  AssembleDiceKey.swift
//  ReadDiceKey
//
//  From undoverlines to a 5x5 grid of faces: lib-read-dicekey/find-faces.cpp (pairing
//  underlines with overlines) and assemble-dicekey.{hpp,cpp} (fitting the grid model and
//  placing every face and stray line into it).
//

import Foundation

// MARK: - find-faces.cpp

struct FaceAndStrayUndoverlinesFound: Sendable {
    var facesFound: [FaceUndoverlines]
    var strayUndoverlines: [Undoverline]
    var pixelsPerFaceEdgeWidth: Float
}

/// `findFacesAndStrayUndoverlines`: pairs each underline with the overline whose implied
/// position agrees best (within a quarter face), and collects the unpaired lines.
func findFacesAndStrayUndoverlines(_ gray: GrayImage) -> FaceAndStrayUndoverlinesFound {
    let undoverlines = findReadableUndoverlines(gray)
    let underlines = undoverlines.underlines
    var overlines = undoverlines.overlines

    var underlineLengths = underlines.map { lineLength($0.line) }
    let medianUnderlineLengthInPixels = medianFloat(&underlineLengths)
    let pixelsPerFaceEdgeWidth = medianUnderlineLengthInPixels / FaceDimensionsFractional.undoverlineLength
    let maxErrorDistance = pixelsPerFaceEdgeWidth / 4  // 2mm

    var strayUndoverlines: [Undoverline] = []
    var facesFound: [FaceUndoverlines] = []

    for underline in underlines {
        // The error distance is how far the overline is from where the underline says it should
        // be, plus how far the underline is from where the overline says it should be.
        var bestMatchIndex = -1
        var bestMatchErrorDistance = maxErrorDistance
        for i in 0..<overlines.count {
            let overline = overlines[i]
            let errorDistance =
                distance2f(underline.center, overline.inferredOpposingUndoverlineCenter) +
                distance2f(overline.center, underline.inferredOpposingUndoverlineCenter)
            if errorDistance <= bestMatchErrorDistance {
                bestMatchIndex = i
                bestMatchErrorDistance = errorDistance
            }
        }
        if bestMatchIndex != -1 {
            facesFound.append(FaceUndoverlines(underline: underline, overline: overlines[bestMatchIndex]))
            overlines.remove(at: bestMatchIndex)
        } else {
            strayUndoverlines.append(underline)
        }
    }
    strayUndoverlines.append(contentsOf: overlines)

    return FaceAndStrayUndoverlinesFound(facesFound: facesFound, strayUndoverlines: strayUndoverlines, pixelsPerFaceEdgeWidth: pixelsPerFaceEdgeWidth)
}

// MARK: - assemble-dicekey.cpp DiceKeyGridModel

/// The 5x5 grid: spacing, rotation and centre, from which every face centre follows.
struct DiceKeyGridModel: Sendable {
    var valid = false
    var distanceBetweenRows: Float = 0
    var distanceBetweenColumns: Float = 0
    var angleInRadians = Float.nan
    var centerPoint = Point2f.zero
    var topLeftPointRotatedClockwise = Point2f.zero

    init() {}

    init(distanceBetweenRows: Float, distanceBetweenColumns: Float, angleInRadians: Float, centerPoint: Point2f) {
        valid = true
        self.distanceBetweenRows = distanceBetweenRows
        self.distanceBetweenColumns = distanceBetweenColumns
        self.angleInRadians = angleInRadians
        self.centerPoint = centerPoint
        topLeftPointRotatedClockwise = Point2f(
            centerPoint.x - 2 * distanceBetweenColumns,
            centerPoint.y - 2 * distanceBetweenRows
        )
    }

    func expectedCenterOfFace(column: Int, row: Int) -> Point2f {
        let faceCenterRotatedClockwise = Point2f(
            topLeftPointRotatedClockwise.x + Float(column) * distanceBetweenColumns,
            topLeftPointRotatedClockwise.y + Float(row) * distanceBetweenRows
        )
        return rotatePointCounterclockwise(faceCenterRotatedClockwise, around: centerPoint, angleInRadians)
    }

    func expectedCenterOfFace(faceIndex: Int) -> Point2f {
        expectedCenterOfFace(column: faceIndex % 5, row: faceIndex / 5)
    }

    /// The index 0-24 of the face whose centre this is, or -1 when the point is not close
    /// enough (within `maxFractionFromCenter` of a face width) to any grid position.
    func inferFaceIndexFromCenterPoint(_ candidateFaceCenter: Point2f, maxFractionFromCenter: Float = 0.25) -> Int {
        let rotatedPoint = rotatePointClockwise(candidateFaceCenter, around: centerPoint, angleInRadians)
        let xDistanceFromLeft = rotatedPoint.x - topLeftPointRotatedClockwise.x
        let yDistanceFromTop = rotatedPoint.y - topLeftPointRotatedClockwise.y
        let approxColumn = xDistanceFromLeft / distanceBetweenColumns
        let approxRow = yDistanceFromTop / distanceBetweenRows
        if approxColumn < -maxFractionFromCenter || approxColumn > (4 + maxFractionFromCenter)
            || approxRow < -maxFractionFromCenter || approxRow > (4 + maxFractionFromCenter) {
            return -1
        }
        if distanceInModCircularRangeFromNegativeNToN(0.0, approxColumn, 0.5) > maxFractionFromCenter
            || distanceInModCircularRangeFromNegativeNToN(0.0, approxRow, 0.5) > maxFractionFromCenter {
            return -1
        }
        // NaN cannot reach here (the range checks above are false for NaN and return -1 only
        // when true), but guard the conversion anyway.
        guard approxColumn.isFinite && approxRow.isFinite else { return -1 }
        let column = cRoundToInt(approxColumn)
        let row = cRoundToInt(approxRow)
        let faceIndex = (row * 5) + column
        return (faceIndex >= 0 && faceIndex < numberOfFaces) ? faceIndex : -1
    }
}

/// `calculateDiceKeyGrid`: finds a face with four others in its row and four in its
/// column (within `maxFractionOfFaceWidthFromRowOrColumnLine` face widths of the row and
/// column lines through it), checks the spacing is even, and builds the grid from it.
///
/// Note: `orderFacesAndInferMissingUndoverlines` passes its `maxMmFromRowOrColumnLine`
/// default of 1.0 into this fraction, so the tolerance is a whole face width, as upstream.
func calculateDiceKeyGrid(_ found: FaceAndStrayUndoverlinesFound, maxFractionOfFaceWidthFromRowOrColumnLine: Float = 0.1) -> DiceKeyGridModel {
    let facesFound = found.facesFound
    let maxPixelsFromRowOrColumnLine = maxFractionOfFaceWidthFromRowOrColumnLine * found.pixelsPerFaceEdgeWidth

    for candidateIntersectionFace in facesFound {
        let gridModel = GridProximity(centerOfElement: candidateIntersectionFace.center(), angleInRadians: candidateIntersectionFace.inferredAngleInRadians())
        var sameColumn: [Point2f] = []
        var sameRow: [Point2f] = []
        for face in facesFound {
            let point = face.center()
            if gridModel.pixelDistanceFromColumn(point) <= maxPixelsFromRowOrColumnLine {
                sameColumn.append(point)
            }
            if gridModel.pixelDistanceFromRow(point) <= maxPixelsFromRowOrColumnLine {
                sameRow.append(point)
            }
        }
        if sameRow.count < 5 || sameColumn.count < 5 {
            continue
        }
        sameRow.sort { $0.x < $1.x }
        sameColumn.sort { $0.y < $1.y }

        let xValuesOfRowsWithinColumn = sameColumn.map { $0.x }
        let yValuesOfRowsWithinColumn = sameColumn.map { $0.y }
        let xValuesOfColumnsWithinRow = sameRow.map { $0.x }
        let yValuesOfColumnsWithinRow = sameRow.map { $0.y }
        let meanXDistanceBetweenColumns = findAndValidateMeanDifference(xValuesOfColumnsWithinRow)
        let meanYDistanceBetweenColumns = findAndValidateMeanDifference(yValuesOfColumnsWithinRow, minBoundEdgeRange: meanXDistanceBetweenColumns / 5)
        let meanYDistanceBetweenRows = findAndValidateMeanDifference(yValuesOfRowsWithinColumn)
        let meanXDistanceBetweenRows = findAndValidateMeanDifference(xValuesOfRowsWithinColumn, minBoundEdgeRange: meanYDistanceBetweenRows / 5)
        if meanXDistanceBetweenColumns.isNaN || meanYDistanceBetweenColumns.isNaN
            || meanXDistanceBetweenRows.isNaN || meanYDistanceBetweenRows.isNaN {
            // The distances between rows or columns are not consistent.
            continue
        }

        // Row and column of the intersection face (the arrays are sorted, so a linear scan).
        let candidateCenter = candidateIntersectionFace.center()
        var rowOfIntersectionFace = 0
        var columnOfIntersectionFace = 0
        while rowOfIntersectionFace < yValuesOfRowsWithinColumn.count && candidateCenter.y > yValuesOfRowsWithinColumn[rowOfIntersectionFace] {
            rowOfIntersectionFace += 1
        }
        while columnOfIntersectionFace < xValuesOfColumnsWithinRow.count && candidateCenter.x > xValuesOfColumnsWithinRow[columnOfIntersectionFace] {
            columnOfIntersectionFace += 1
        }

        // The centre face is at row 2, column 2.
        let centerX = candidateCenter.x
            + (Float(2 - rowOfIntersectionFace) * meanXDistanceBetweenRows)
            + (Float(2 - columnOfIntersectionFace) * meanXDistanceBetweenColumns)
        let centerY = candidateCenter.y
            + (Float(2 - rowOfIntersectionFace) * meanYDistanceBetweenRows)
            + (Float(2 - columnOfIntersectionFace) * meanYDistanceBetweenColumns)

        let angleInRadians = angleOfLineInSignedRadians2f(Point2f(0, 0), Point2f(meanXDistanceBetweenColumns, meanYDistanceBetweenColumns))
        let distanceBetweenRows = distance2f(meanXDistanceBetweenColumns, meanYDistanceBetweenColumns)
        let distanceBetweenColumns = distance2f(meanXDistanceBetweenRows, meanYDistanceBetweenRows)

        return DiceKeyGridModel(
            distanceBetweenRows: distanceBetweenRows,
            distanceBetweenColumns: distanceBetweenColumns,
            angleInRadians: angleInRadians,
            centerPoint: Point2f(centerX, centerY)
        )
    }
    return DiceKeyGridModel()
}

// MARK: - assemble-dicekey.cpp orderFacesAndInferMissingUndoverlines

struct FacesOrderedWithMissingFacesInferredFromUnderlines: Sendable {
    var valid = false
    var orderedFaces: [FaceUndoverlines] = []
    /// The angle of the grid as it lies in the image (no canonical rotation applied).
    var angleInRadiansNonCanonicalForm = Float.nan
    var pixelsPerFaceEdgeWidth: Float = 0
}

/// `orderFacesAndInferMissingUndoverlines`: places the paired faces into the grid, then the
/// stray lines (reading the opposite line where the stray says it should be), leaving
/// faces with neither line as empty entries.
func orderFacesAndInferMissingUndoverlines(_ gray: GrayImage, _ found: FaceAndStrayUndoverlinesFound, maxMmFromRowOrColumnLine: Float = 1.0) -> FacesOrderedWithMissingFacesInferredFromUnderlines {
    let grid = calculateDiceKeyGrid(found, maxFractionOfFaceWidthFromRowOrColumnLine: maxMmFromRowOrColumnLine)
    if !grid.valid {
        return FacesOrderedWithMissingFacesInferredFromUnderlines()
    }
    var orderedFaces = [FaceUndoverlines](repeating: FaceUndoverlines(), count: numberOfFaces)
    for faceFound in found.facesFound {
        let faceIndex = grid.inferFaceIndexFromCenterPoint(faceFound.center())
        if faceIndex >= 0 {
            orderedFaces[faceIndex] = faceFound
        }
    }
    for undoverline in found.strayUndoverlines {
        let faceIndex = grid.inferFaceIndexFromCenterPoint(undoverline.inferredCenterOfFace)
        if faceIndex >= 0 {
            if undoverline.isOverline && !orderedFaces[faceIndex].overline.found {
                orderedFaces[faceIndex] = FaceUndoverlines(
                    underline: orderedFaces[faceIndex].underline.found
                        ? orderedFaces[faceIndex].underline
                        : readUndoverline(gray, rectEncompassingLine: undoverline.inferredOpposingUndoverlineRotatedRect),
                    overline: undoverline
                )
            } else if !undoverline.isOverline && !orderedFaces[faceIndex].underline.found {
                orderedFaces[faceIndex] = FaceUndoverlines(
                    underline: undoverline,
                    overline: orderedFaces[faceIndex].overline.found
                        ? orderedFaces[faceIndex].overline
                        : readUndoverline(gray, rectEncompassingLine: undoverline.inferredOpposingUndoverlineRotatedRect)
                )
            }
        }
    }
    // The C++ replaces faces with neither line by a centre-only subclass, but storing it in
    // a vector<FaceUndoverlines> slices that away, so such faces keep centre (0, 0). Kept
    // as upstream behaves.
    return FacesOrderedWithMissingFacesInferredFromUnderlines(
        valid: true,
        orderedFaces: orderedFaces,
        angleInRadiansNonCanonicalForm: grid.angleInRadians,
        pixelsPerFaceEdgeWidth: found.pixelsPerFaceEdgeWidth
    )
}
