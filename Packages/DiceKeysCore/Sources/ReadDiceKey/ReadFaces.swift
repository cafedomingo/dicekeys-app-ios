//
//  ReadFaces.swift
//  ReadDiceKey
//
//  lib-read-dicekey/read-faces.cpp: one frame in, up to 25 faces out.
//

import Foundation

/// read-faces.h `ReadFaceResult`.
struct ReadFaceResult: Sendable {
    var success: Bool
    var faces: [FaceRead]
    var angleInRadiansNonCanonicalForm: Float
    var pixelsPerFaceEdgeWidth: Float
}

/// read-faces.cpp `readFaces`: locates the undoverlines, fits the grid, then OCRs every
/// face that has at least one decoded line to orient it.
func readFaces(_ gray: GrayImage) -> ReadFaceResult {
    let faceAndStrayUndoverlinesFound = findFacesAndStrayUndoverlines(gray)
    let orderedFacesResult = orderFacesAndInferMissingUndoverlines(gray, faceAndStrayUndoverlinesFound)
    var orderedFaces: [FaceRead] = []
    orderedFaces.reserveCapacity(orderedFacesResult.orderedFaces.count)
    let angleOfDiceKeyInRadiansNonCanonicalForm = orderedFacesResult.angleInRadiansNonCanonicalForm

    for face in orderedFacesResult.orderedFaces {
        if !(face.underline.determinedIfUnderlineOrOverline || face.overline.determinedIfUnderlineOrOverline) {
            // Without an overline or underline to orient the face, we can't read it.
            orderedFaces.append(FaceRead(undoverlines: face, orientation: nil, ocrLetters: [], ocrDigits: []))
            continue
        }
        // The black/white threshold is the mean of the thresholds used for the underline and
        // the overline, or that of whichever line is present.
        let whiteBlackThreshold: UInt8
        if face.underline.found && face.overline.found {
            whiteBlackThreshold = UInt8((UInt(face.underline.whiteBlackThreshold) + UInt(face.overline.whiteBlackThreshold)) / 2)
        } else if face.underline.found {
            whiteBlackThreshold = face.underline.whiteBlackThreshold
        } else {
            whiteBlackThreshold = face.overline.whiteBlackThreshold
        }
        let charsRead = readCharactersOnFace(
            gray,
            faceCenter: face.center(),
            angleRadians: face.inferredAngleInRadians(),
            pixelsPerFaceEdgeWidth: faceAndStrayUndoverlinesFound.pixelsPerFaceEdgeWidth,
            whiteBlackThreshold: whiteBlackThreshold
        )

        let orientationInRadians = face.inferredAngleInRadians() - angleOfDiceKeyInRadiansNonCanonicalForm
        let orientationInClockwiseRotationsFloat = orientationInRadians * Float(4.0 / (2.0 * Double.pi))
        // C++: uchar(round(f) + 4) % 4
        let orientationInClockwiseRotationsFromUpright = clockwiseTurnsToRange0To3(cRoundToInt(orientationInClockwiseRotationsFloat) + 4)
        orderedFaces.append(FaceRead(
            undoverlines: face,
            orientation: orientationInClockwiseRotationsFromUpright,
            ocrLetters: [charsRead.lettersMostLikelyFirst[0].character, charsRead.lettersMostLikelyFirst[1].character],
            ocrDigits: [charsRead.digitsMostLikelyFirst[0].character, charsRead.digitsMostLikelyFirst[1].character]
        ))
    }

    return ReadFaceResult(
        success: orderedFacesResult.valid,
        faces: orderedFaces,
        angleInRadiansNonCanonicalForm: orderedFacesResult.angleInRadiansNonCanonicalForm,
        pixelsPerFaceEdgeWidth: orderedFacesResult.pixelsPerFaceEdgeWidth
    )
}
