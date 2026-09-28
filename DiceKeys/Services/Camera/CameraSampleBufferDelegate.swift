//
//  CameraSampleBufferDelegate.swift
//  DiceKeys
//
//  Created by Stuart Schechter on 2020/11/23.
//

import AVFoundation
import ReadDiceKey

/// The one `NSObject` subclass in the app: AVFoundation requires an
/// `AVCaptureVideoDataOutputSampleBufferDelegate`, which must be an `NSObject`.
///
/// `@unchecked Sendable` because AVFoundation calls `captureOutput` on the serial
/// queue handed to `setSampleBufferDelegate`, while the session is configured
/// from a background task. All of its state is either immutable or an actor.
///
/// `nonisolated` so the delegate method is never main-actor-isolated even if the
/// module is built with main-actor default isolation.
nonisolated final class CameraSampleBufferDelegate: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate, @unchecked Sendable {
    private let processor: DiceKeyFrameProcessor
    private let onFrame: @MainActor @Sendable (ScannedFrame) -> Void

    init(processor: DiceKeyFrameProcessor, onFrame: @escaping @MainActor @Sendable (ScannedFrame) -> Void) {
        self.processor = processor
        self.onFrame = onFrame
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        // Skip the copy when the previous frame is still being scanned. The buffers arrive
        // rotated by AVFoundation (see CameraSession.applyCaptureRotation), so the square
        // is already the way the user sees it.
        guard !processor.isBusy,
              let imageBuffer = sampleBuffer.imageBuffer,
              let image = GrayImage(centeredSquareOf: imageBuffer) else { return }
        processor.trySubmit(image, onResult: onFrame)
    }
}
