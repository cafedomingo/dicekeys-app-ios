//
//  TransferSticker.swift
//  DiceKeys
//

import SwiftUI

struct TransferStickerInstructions: View {
    let diceKey: DiceKey
    var faceIndex: Int

    var face: Face {
        diceKey.faces[faceIndex]
    }

    var stickerSheet: StickerSheetForFace {
        StickerSheetForFace(face: face)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(
                "Remove the \(face.letterAndDigit) sticker from the sheet with letters \(stickerSheet.firstLetter.rawValue) through \(stickerSheet.lastLetter.rawValue)."
            )
            .font(.title)
            .minimumScaleFactor(0.5)
            if face.orientationAsLowercaseLetterTrbl != .Top {
                Text("Rotate it so the top faces to the \(face.orientationAsLowercaseLetterTrbl.asFacingString).")
                    .font(.title)
                    .minimumScaleFactor(0.5)
            }
            Text(
                "Place it squarely covering the target rectangle\( faceIndex == 0 ? " at the top left of the target sheet" : "")."
            )
            .font(.title)
            .minimumScaleFactor(0.5)
        }
    }
}

struct TransferSticker: View {
    @State private var bounds: CGSize = .zero
    let diceKey: DiceKey
    var faceIndex: Int

    let sideMarginFraction: CGFloat = 0
    let centerMarginFraction: CGFloat = 0.05
    var aspectRatio: CGFloat {
        2 * StickerTargetSheetSpecification.shortSideOverLongSide + 2 * sideMarginFraction + 2 * centerMarginFraction
    }

    var fractionalWidthOfPortraitSheet: CGFloat {
        (CGFloat(1) - (2 * sideMarginFraction + centerMarginFraction)) / 2
    }
    var totalHeight: CGFloat {
        min(
            bounds.height,
            (bounds.width * fractionalWidthOfPortraitSheet) * StickerTargetSheetSpecification.longSideOverShortSide
        )
    }
    var portraitSheetSize: CGSize {
        CGSize(width: totalHeight * StickerTargetSheetSpecification.shortSideOverLongSide, height: totalHeight)
    }
    var totalWidth: CGFloat {
        portraitSheetSize.width / fractionalWidthOfPortraitSheet
    }

    var faceSizeModel: DiceKeySizeModel { DiceKeySizeModel(portraitSheetSize.width) }

    var face: Face {
        diceKey.faces[faceIndex]
    }

    private var stickerSheet: StickerSheetForFace {
        StickerSheetForFace(face: face)
    }

    var keyColumn: Int {
        Int(faceIndex % 5)
    }
    var keyRow: Int {
        Int(faceIndex / 5)
    }

    /// From the left edge of the left sheet to the center of the sticker's face, then a little
    /// toward its right edge.
    var lineStart: CGPoint {
        let faceCenterX =
            sideMarginFraction * totalWidth + portraitSheetSize.width / 2
            + (stickerSheet.column - 2) * faceSizeModel.stepSize
        let faceCenterY = portraitSheetSize.height / 2 + (stickerSheet.row - 2.5) * faceSizeModel.stepSize
        return CGPoint(x: faceCenterX + faceSizeModel.faceSize * 0.4, y: faceCenterY)
    }

    /// From the right edge of the right sheet to the center of the target face, then a little
    /// toward its left edge.
    var lineEnd: CGPoint {
        let faceCenterX =
            (CGFloat(1) - sideMarginFraction) * totalWidth - portraitSheetSize.width / 2
            + (CGFloat(keyColumn) - 2) * faceSizeModel.stepSize
        let faceCenterY = portraitSheetSize.height / 2 + (CGFloat(keyRow) - 2) * faceSizeModel.stepSize
        return CGPoint(x: faceCenterX - faceSizeModel.faceSize * 0.4, y: faceCenterY)
    }

    var body: some View {
        ChildSizeReader(size: $bounds) {
            HStack(alignment: .center, spacing: 0) {
                StickerSheet(showLetter: face.letter, highlightFaceWithDigit: face.digit)
                Spacer().frame(maxWidth: bounds.width * centerMarginFraction)
                StickerTargetSheet(diceKey: diceKey, showLettersBeforeIndex: faceIndex, atDieIndex: faceIndex)
            }.overlay(
                Path { path in
                    path.move(to: lineStart)
                    path.addLine(to: lineEnd)
                }.stroke(Color.Depiction.kitBlue, lineWidth: 2.0)
            )
        }.aspectRatio(aspectRatio, contentMode: .fit)
    }
}

#Preview {
    VStack {
        TransferSticker(diceKey: DiceKey.createFromRandom(), faceIndex: 24)
        TransferSticker(diceKey: DiceKey.createFromRandom(), faceIndex: 0)
    }
}
