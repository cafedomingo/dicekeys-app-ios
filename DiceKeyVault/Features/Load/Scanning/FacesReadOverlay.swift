//
//  FacesReadOverlay.swift
//  DiceKeyVault
//

import DiceKeySpecification
import ReadDiceKey
import SwiftUI

/// How far the letter's and the digit's centers sit either side of the face's center, as a
/// fraction of the face's size.
private let glyphCenterOffset: CGFloat = {
    let glyphWidth =
        (FaceDimensionsFractional.textRegionWidth - FaceDimensionsFractional.spaceBetweenLetterAndDigit) / 2
    return (FaceDimensionsFractional.spaceBetweenLetterAndDigit + glyphWidth) / 2
}()

/// Dims the camera preview except for a window over the middle three quarters of the square,
/// the size a whole DiceKey should look. The scanner reads a key that size as well as one
/// filling the frame, and asking for no more keeps the phone far enough back to focus and to
/// keep the whole key in view.
struct ScanningTarget: Shape {
    /// How much of the square's side the window takes up. CameraSession zooms for it.
    static let windowFraction: CGFloat = 3 / 4

    func path(in rect: CGRect) -> Path {
        var path = Path(rect)
        let side = min(rect.width, rect.height) * Self.windowFraction
        let window = CGRect(x: rect.midX - side / 2, y: rect.midY - side / 2, width: side, height: side)
        path.addRoundedRect(in: window, cornerSize: CGSize(width: 0.06 * side, height: 0.06 * side))
        return path
    }
}

/// Draws the letters and digits the scanner has read on top of the camera
/// preview, each rotated to match its die. Until a face has been read, shows the scanning
/// target instead.
struct FacesReadOverlay: View {
    let renderedSize: CGSize
    let dice: [DieInFrame]
    let imageFrameSize: CGSize

    var body: some View {
        if !dice.contains(where: { $0.face != nil }) || imageFrameSize.width == 0 || imageFrameSize.height == 0 {
            ScanningTarget()
                .fill(Color.cameraDim, style: FillStyle(eoFill: true))
                .frame(width: renderedSize.width, height: renderedSize.height)
        } else {
            Canvas { context, size in
                let scale = size.width / imageFrameSize.width
                for die in dice {
                    guard let face = die.face else { continue }
                    let faceSize = die.size * scale
                    var faceContext = context
                    faceContext.translateBy(x: die.center.x * scale, y: die.center.y * scale)
                    faceContext.rotate(by: Angle(radians: die.angle))
                    let font = Font.custom("Inconsolata-Bold", size: faceSize * FaceDimensionsFractional.fontSize)
                    let offset = glyphCenterOffset * faceSize
                    for (glyph, x) in [(face.letter.rawValue, -offset), (face.digit.rawValue, offset)] {
                        faceContext.draw(
                            Text(glyph).font(font).foregroundStyle(Color.accent), at: CGPoint(x: x, y: 0),
                            anchor: .center)
                    }
                }
            }
            .frame(width: renderedSize.width, height: renderedSize.height)
            .allowsHitTesting(false)
        }
    }
}

#Preview {
    let dice = DiceKey.example.faces.enumerated().map { index, face in
        let turns = FaceOrientationLetterTrbl.allCases.firstIndex(of: face.orientation)!
        return DieInFrame(
            center: CGPoint(x: 100 * (index % 5 + 1), y: 100 * (index / 5 + 1)),
            angle: Double(turns) * .pi / 2,
            size: 50,
            face: ScannedFace(letter: face.letter, digit: face.digit, clockwiseTurns: turns)
        )
    }
    FacesReadOverlay(
        renderedSize: CGSize(width: 600, height: 600), dice: dice, imageFrameSize: CGSize(width: 600, height: 600)
    )
    .background(Color.camera)
}
