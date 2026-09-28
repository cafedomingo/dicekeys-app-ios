//
//  DiceKeyScanModel.swift
//  DiceKeys
//
//  Created by Kevin Shah on 27/01/21.
//

import Foundation
import Observation
import ReadDiceKey

/// Per-frame results from the scanner, published on the main actor. Only the
/// views that read `frameCount` or `dice` re-render on every frame.
@MainActor @Observable
final class DiceKeyScanModel {
    private(set) var frameCount = 0
    private(set) var imageFrameSize: CGSize = .zero
    private(set) var dice: [DieInFrame] = []

    /// Set once, when every face of the DiceKey has been read.
    private(set) var completedDiceKey: DiceKey?

    func apply(_ frame: ScannedFrame) {
        frameCount += 1
        if imageFrameSize != frame.size {
            imageFrameSize = frame.size
        }
        dice = frame.dice
        guard completedDiceKey == nil, let faces = frame.diceKey else {
            return
        }
        completedDiceKey = DiceKey(faces)
    }
}
