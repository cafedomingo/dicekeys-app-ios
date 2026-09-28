//
//  FacesReadOverlay.swift
//  DiceKeys
//
//  Created by Stuart Schechter on 2020/11/20.
//

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

/// Draws the letters and digits the scanner has read on top of the camera
/// preview, each rotated to match its die. Until a DiceKey is in view, shows the
/// scanning target overlay instead.
struct FacesReadOverlay: View {
    let renderedSize: CGSize
    let dice: [DieInFrame]
    let imageFrameSize: CGSize

    var body: some View {
        if dice.isEmpty || imageFrameSize.width == 0 || imageFrameSize.height == 0 {
            Image("Scanning Overlay")
                .resizable()
                .foregroundStyle(Color.Camera.dim)
                .frame(width: renderedSize.width, height: renderedSize.height)
        } else {
            Canvas { context, size in
                let scale = size.width / imageFrameSize.width
                for die in dice {
                    guard let face = die.face else { continue }
                    let faceSize = die.size * scale
                    let angle = Angle(radians: die.angle)
                    let coordinateSystemFromCenterOfDie = AngularCoordinateSystem(
                        zeroPoint: CGPoint(x: die.center.x * scale, y: die.center.y * size.height / imageFrameSize.height),
                        angle: angle,
                        scalingFactor: faceSize
                    )
                    let font = Font.custom("Inconsolata-Bold", size: faceSize * FaceDimensionsFractional.fontSize)
                    draw(String(face.letter), in: context, at: coordinateSystemFromCenterOfDie.pointAt(offset: letterOffset), angle: angle, font: font)
                    draw(String(face.digit), in: context, at: coordinateSystemFromCenterOfDie.pointAt(offset: digitOffset), angle: angle, font: font)
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
            face: ScannedFace(letter: Character(face.letter.rawValue), digit: Character(face.digit.rawValue), clockwiseTurns: turns)
        )
    }
    FacesReadOverlay(renderedSize: CGSize(width: 600, height: 600), dice: dice, imageFrameSize: CGSize(width: 600, height: 600))
        .background(Color.Camera.backdrop)
}
