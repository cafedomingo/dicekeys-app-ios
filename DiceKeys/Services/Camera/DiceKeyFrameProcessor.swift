//
//  DiceKeyFrameProcessor.swift
//  DiceKeys
//
//  Owns the (non-Sendable) `DiceKeyScanner` and runs it off the main actor.
//

import Foundation
import ReadDiceKey
import Synchronization

/// The scanner's output for one camera frame.
nonisolated struct ScannedFrame: Sendable {
    /// JSON array of faces read, decoded on the main actor by `FaceRead.fromJson`.
    let readResultJSON: String
    let width: Int
    let height: Int
    /// True once the scanner has read a complete DiceKey.
    let isFinished: Bool
}

/// Processes RGBA frames with `DiceKeyScanner`, one at a time, dropping any
/// frame that arrives while another is being scanned.
actor DiceKeyFrameProcessor {
    private let scanner = DiceKeyScanner()
    private nonisolated let inFlight = Mutex(false)

    init() {}

    /// True while a frame is being scanned; check this before doing the work of
    /// converting a sample buffer that would only be dropped.
    nonisolated var isBusy: Bool {
        inFlight.withLock { $0 }
    }

    /// Submits a frame unless one is already in flight. Returns false when the
    /// frame was dropped. `onResult` runs on the main actor for every frame scanned.
    @discardableResult
    nonisolated func trySubmit(
        rgba: Data,
        width: Int,
        height: Int,
        onResult: @escaping @MainActor @Sendable (ScannedFrame) -> Void
    ) -> Bool {
        let claimed = inFlight.withLock { busy -> Bool in
            if busy { return false }
            busy = true
            return true
        }
        guard claimed else { return false }
        // The scan is what the user is waiting on, and the scanner fans its contour passes
        // out with concurrentPerform, so ask for the performance cores.
        Task(priority: .userInitiated) {
            let frame = await self.process(rgba: rgba, width: width, height: height)
            self.inFlight.withLock { $0 = false }
            await onResult(frame)
        }
        return true
    }

    private func process(rgba: Data, width: Int, height: Int) -> ScannedFrame {
        let finished = scanner.process(rgba: rgba, width: width, height: height)
        return ScannedFrame(
            readResultJSON: scanner.readResultJSON,
            width: width,
            height: height,
            isFinished: finished
        )
    }
}
