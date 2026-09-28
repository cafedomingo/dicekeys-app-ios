//
//  DiceKeyFrameProcessor.swift
//  DiceKeys
//
//  Owns the `DiceKeyScanner` and runs it off the main actor.
//

import CoreGraphics
import ReadDiceKey
import Synchronization

/// The scanner's output for one camera frame.
nonisolated struct ScannedFrame: Sendable {
    /// The dice found in the frame, in frame pixels.
    let dice: [DieInFrame]
    let size: CGSize
    /// All 25 faces, once every one has been read.
    let diceKey: [ScannedFace]?
}

/// Scans frames with `DiceKeyScanner`, one at a time, dropping any frame that
/// arrives while another is being scanned.
actor DiceKeyFrameProcessor {
    private var scanner = DiceKeyScanner()
    private nonisolated let inFlight = Mutex(false)

    init() {}

    /// True while a frame is being scanned; check this before copying a sample
    /// buffer that would only be dropped.
    nonisolated var isBusy: Bool {
        inFlight.withLock { $0 }
    }

    /// Submits a frame unless one is already in flight. Returns false when the
    /// frame was dropped. `onResult` runs on the main actor for every frame scanned.
    @discardableResult
    nonisolated func trySubmit(
        _ image: GrayImage,
        onResult: @escaping @MainActor @Sendable (ScannedFrame) -> Void
    ) -> Bool {
        let claimed = inFlight.withLock { busy -> Bool in
            if busy { return false }
            busy = true
            return true
        }
        guard claimed else { return false }
        // The scan is what the user is waiting on, and the scanner spreads its thresholds
        // across cores with concurrentPerform, so ask for the performance cores.
        Task(priority: .userInitiated) {
            let frame = await self.process(image)
            self.inFlight.withLock { $0 = false }
            await onResult(frame)
        }
        return true
    }

    private func process(_ image: GrayImage) -> ScannedFrame {
        let dice = scanner.scan(image)
        return ScannedFrame(dice: dice, size: CGSize(width: image.width, height: image.height), diceKey: scanner.diceKey)
    }
}
