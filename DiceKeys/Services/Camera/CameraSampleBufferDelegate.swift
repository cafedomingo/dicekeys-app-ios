//
//  CameraSampleBufferDelegate.swift
//  DiceKeys
//
//  Created by Stuart Schechter on 2020/11/23.
//

import AVFoundation
import ReadDiceKey

/// The scanner's output for one camera frame.
nonisolated struct ScannedFrame: Sendable {
    /// The dice found in the frame, in frame pixels.
    let dice: [DieInFrame]
    let size: CGSize
    /// All 25 faces, once every one has been read and they make a DiceKey.
    let diceKey: [ScannedFace]?
    /// All 25 faces, once every one has been read, whatever they are.
    let allFaces: [ScannedFace]?
}

/// Scans each camera frame and hands the result to the main actor. The one `NSObject`
/// subclass in the app: AVFoundation requires an `AVCaptureVideoDataOutputSampleBufferDelegate`,
/// which must be an `NSObject`.
///
/// Frames are scanned where AVFoundation delivers them, on `queue`. While a scan runs the
/// queue is busy, and the output, which discards late frames, drops the frames that arrive
/// meanwhile. `@unchecked Sendable` because the scanner is only ever touched on that queue,
/// which is the same for every output the delegate serves, so a camera switch cannot overlap
/// two scans.
///
/// `nonisolated` so the delegate method is never main-actor-isolated even if the
/// module is built with main-actor default isolation.
nonisolated final class CameraSampleBufferDelegate: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate, @unchecked Sendable {
    /// The single DispatchQueue in the app: AVFoundation requires a serial queue for
    /// sample-buffer delivery, and the frames are scanned on it while the user waits.
    let queue = DispatchQueue(label: "com.dicekeys.sampleBuffers", qos: .userInitiated)
    private var scanner = DiceKeyScanner()
    private let onFrame: @MainActor @Sendable (ScannedFrame) -> Void

    init(onFrame: @escaping @MainActor @Sendable (ScannedFrame) -> Void) {
        self.onFrame = onFrame
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        // The buffers arrive rotated by AVFoundation (see CameraSession.applyCaptureRotation),
        // so the square is already the way the user sees it.
        guard let imageBuffer = sampleBuffer.imageBuffer,
              let image = GrayImage(centeredSquareOf: imageBuffer) else { return }
        let frame = ScannedFrame(
            dice: scanner.scan(image),
            size: CGSize(width: image.width, height: image.height),
            diceKey: scanner.diceKey,
            allFaces: scanner.allFaces
        )
        let onFrame = self.onFrame
        Task { @MainActor in onFrame(frame) }
    }
}
