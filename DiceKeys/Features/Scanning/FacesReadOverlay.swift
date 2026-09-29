//
//  FacesReadOverlay.swift
//  DiceKeys
//
//  Created by Stuart Schechter on 2020/11/20.
//

import DiceKeySpecification
import ReadDiceKey
import SwiftUI

struct AngularCoordinateSystem {
    private let zeroPoint: CGPoint
    private let cosAngle: CGFloat
    private let sinAngle: CGFloat

    init(zeroPoint: CGPoint, angle: Angle, scalingFactor: CGFloat) {
        self.zeroPoint = zeroPoint
        self.cosAngle = CGFloat(cos(angle.radians)) * scalingFactor
        self.sinAngle = CGFloat(sin(angle.radians)) * scalingFactor
    }

    func pointAt(offset: CGPoint) -> CGPoint {
        CGPoint(
            x: zeroPoint.x + offset.x * cosAngle - offset.y * sinAngle,
            y: zeroPoint.y + offset.x * sinAngle + offset.y * cosAngle
        )
    }
}

private let charWidthFractional: CGFloat = (FaceDimensionsFractional.textRegionWidth - FaceDimensionsFractional.spaceBetweenLetterAndDigit) / 2
private let xDistToCharCenter: CGFloat = (FaceDimensionsFractional.spaceBetweenLetterAndDigit / 2) + (charWidthFractional / 2)
private let letterOffset = CGPoint(x: -xDistToCharCenter, y: 0)
private let digitOffset = CGPoint(x: xDistToCharCenter, y: 0)

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
                .fill(Color.Camera.dim, style: FillStyle(eoFill: true))
                .frame(width: renderedSize.width, height: renderedSize.height)
        } else {
            Canvas { context, size in
                let scale = size.width / imageFrameSize.width
                for die in dice {
                    guard let face = die.face else { continue }
                    let faceSize = die.size * scale
                    let angle = Angle(radians: die.angle)
                    let coordinateSystemFromCenterOfDie = AngularCoordinateSystem(
                        zeroPoint: CGPoint(x: die.center.x * scale, y: die.center.y * scale),
                        angle: angle,
                        scalingFactor: faceSize
                    )
                    let font = Font.custom("Inconsolata-Bold", size: faceSize * FaceDimensionsFractional.fontSize)
                    draw(face.letter.rawValue, in: context, at: coordinateSystemFromCenterOfDie.pointAt(offset: letterOffset), angle: angle, font: font)
                    draw(face.digit.rawValue, in: context, at: coordinateSystemFromCenterOfDie.pointAt(offset: digitOffset), angle: angle, font: font)
                }
            }
            .frame(width: renderedSize.width, height: renderedSize.height)
            .allowsHitTesting(false)
        }
    }

    private func draw(_ string: String, in context: GraphicsContext, at point: CGPoint, angle: Angle, font: Font) {
        var rotated = context
        rotated.translateBy(x: point.x, y: point.y)
        rotated.rotate(by: angle)
        rotated.draw(
            Text(string).font(font).foregroundStyle(Color.Camera.faceRead),
            at: .zero,
            anchor: .center
        )
    }
}

#Preview {
    let dice = DiceKey.createFromRandom().faces.enumerated().map { index, face in
        let turns = FaceOrientationLetterTrbl.allCases.firstIndex(of: face.orientationAsLowercaseLetterTrbl)!
        return DieInFrame(
            center: CGPoint(x: 100 * (index % 5 + 1), y: 100 * (index / 5 + 1)),
            angle: Double(turns) * .pi / 2,
            size: 50,
            face: ScannedFace(letter: face.letter, digit: face.digit, clockwiseTurns: turns)
        )
    }
    FacesReadOverlay(renderedSize: CGSize(width: 600, height: 600), dice: dice, imageFrameSize: CGSize(width: 600, height: 600))
        .background(Color.Camera.backdrop)
}
