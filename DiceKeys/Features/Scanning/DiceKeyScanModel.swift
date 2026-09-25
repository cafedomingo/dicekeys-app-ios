//
//  DiceKeyScanModel.swift
//  DiceKeys
//
//  Created by Kevin Shah on 27/01/21.
//

import Foundation
import Observation

/// Per-frame results from the scanner, published on the main actor. Only the
/// views that read `frameCount` or `facesRead` re-render on every frame.
@MainActor @Observable
final class DiceKeyScanModel {
    private(set) var frameCount = 0
    private(set) var imageFrameSize: CGSize = .zero
    private(set) var facesRead: [FaceRead] = []

    /// Set once, when a complete, error-free DiceKey has been read.
    private(set) var completedDiceKey: DiceKey?

    func apply(_ frame: ScannedFrame) {
        frameCount += 1
        let size = CGSize(width: frame.width, height: frame.height)
        if imageFrameSize != size {
            imageFrameSize = size
        }
        let faces = FaceRead.fromJson(frame.readResultJSON) ?? []
        facesRead = faces

        guard completedDiceKey == nil,
              faces.count == 25,
              faces.allSatisfy({ $0.errors.isEmpty }),
              let diceKey = try? DiceKey(faces) else {
            return
        }
        // Frames are rotated by AVFoundation before the scanner sees them, so the faces
        // are already in the orientation the user is looking at. The pipeline used to
        // apply a fixed 90° turn here to compensate for the raw landscape-native buffer.
        completedDiceKey = diceKey
    }

    func reset() {
        frameCount = 0
        facesRead = []
        completedDiceKey = nil
    }
}
