//
//  StickySheet.swift
//  DiceKeys
//
//  Created by Stuart Schechter on 2020/12/02.
//

import SwiftUI

private let nativeHeightOverWidth = CGFloat(155.0/130.0)
private let nativeWidthOverHeight = 1/nativeHeightOverWidth
private let lettersPerStickySheet = 5

struct StickerSheet: View {
    var showLetter: FaceLetter = FaceLetter.A
    var highlightFaceWithDigit: FaceDigit?

    @State private var bounds: CGSize = .zero

    var height: CGFloat {
        min(bounds.height,
            nativeHeightOverWidth * bounds.width
        )
    }

    var pageIndex: Int {
        Int(faceLetterIndexes[showLetter] ?? 0) / lettersPerStickySheet
    }
    var firstLetterIndex: Int {
        pageIndex * lettersPerStickySheet
    }

    var width: CGFloat {
        height * nativeWidthOverHeight
    }

    var faceSizeModel: DiceKeySizeModel { DiceKeySizeModel(width) }
    var faceSize: CGFloat { faceSizeModel.faceSize }
    var faceStepSize: CGFloat { faceSizeModel.stepSize }

    var body: some View {
        CalculateBounds(bounds: $bounds) {
        ZStack(alignment: .center) {
            // The sheet
            Rectangle()
                .size(width: width, height: height)
                .fill(Color.Depiction.stickerSheet)
                .border(Color.Depiction.stickerSheetEdge)
                .frame(width: width, height: height)
            // The dice
            ForEach(0..<5, id: \.self) { letterIndexOnPage in
                ForEach(0..<6, id: \.self) { digitIndex in
                    let letter = FaceLetters[firstLetterIndex + letterIndexOnPage]
                    let isHighlighted = showLetter == letter && highlightFaceWithDigit == FaceDigits[digitIndex]
                    DieView(
                        face: Face(letter: letter, digit: FaceDigits[digitIndex], orientationAsLowercaseLetterTrbl: FaceOrientationLetterTrbl.Top),
                        dieSize: faceSize,
                        penColor: isHighlighted ? Color.Depiction.stickerPenFaded : Color.Depiction.diePen,
                        faceSurfaceColor: isHighlighted ? Color.Depiction.highlighter : Color.Depiction.dieFace,
                        faceBorderColor: Color.Depiction.stickerFaceBorder
                    ).offset(
                        x: CGFloat(-2 + (letterIndexOnPage)) * faceStepSize,
                        y: CGFloat(-2.5 + CGFloat(digitIndex)) * faceStepSize
                    )
                }
            }
        }}.aspectRatio(nativeWidthOverHeight, contentMode: .fit)
    }
}

#Preview {
    VStack {
        StickerSheet(showLetter: FaceLetter.Z, highlightFaceWithDigit: FaceDigit._2)
        StickerSheet(showLetter: FaceLetter.S, highlightFaceWithDigit: FaceDigit._5)
    }
}
