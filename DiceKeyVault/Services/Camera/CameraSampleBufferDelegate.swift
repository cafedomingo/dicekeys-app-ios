//
//  CameraSampleBufferDelegate.swift
//  DiceKeyVault
//

import AVFoundation
import ReadDiceKey
import Vision

/// The scanner's output for one camera frame.
nonisolated struct ScannedFrame: Sendable {
    /// The dice found in the frame, in frame pixels.
    let dice: [DieInFrame]
    let size: CGSize
    /// All 25 faces, once every one has been read and they make a DiceKey.
    let diceKey: [ScannedFace]?
    /// The text of a list card's or recovery sheet's code in view.
    var code: String?
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
nonisolated final class CameraSampleBufferDelegate: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate,
    @unchecked Sendable
{
    /// The single DispatchQueue in the app: AVFoundation requires a serial queue for
    /// sample-buffer delivery, and the frames are scanned on it while the user waits.
    let queue = DispatchQueue(label: "com.dicekeys.sampleBuffers", qos: .userInitiated)
    /// Codes are looked for on every fifth frame, which finds one within a moment while
    /// leaving the other frames to the dice.
    private static let codeFrameInterval = 5
    /// Both, whatever the recovery sheet prints today, so sheets printed before a change still read.
    private static let codeSymbologies: [VNBarcodeSymbology] = [.qr, .aztec]
    private var scanner = DiceKeyScanner()
    private var frameCount = 0
    private let onFrame: @MainActor @Sendable (ScannedFrame) -> Void

    init(onFrame: @escaping @MainActor @Sendable (ScannedFrame) -> Void) {
        self.onFrame = onFrame
    }

    func captureOutput(
        _ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection
    ) {
        // The buffers arrive rotated by AVFoundation (see CameraSession.applyCaptureRotation),
        // so the square is already the way the user sees it.
        guard let imageBuffer = sampleBuffer.imageBuffer,
            let image = GrayImage(centeredSquareOf: imageBuffer)
        else { return }
        frameCount += 1
        let frame = ScannedFrame(
            dice: scanner.scan(image),
            size: CGSize(width: image.width, height: image.height),
            diceKey: scanner.diceKey,
            code: frameCount.isMultiple(of: Self.codeFrameInterval) ? Self.code(in: imageBuffer) : nil
        )
        let onFrame = self.onFrame
        Task { @MainActor in onFrame(frame) }
    }

    /// Runs here, synchronously: Vision's async request can't run inside this delegate.
    private static func code(in imageBuffer: CVPixelBuffer) -> String? {
        let request = VNDetectBarcodesRequest()
        request.symbologies = codeSymbologies
        try? VNImageRequestHandler(cvPixelBuffer: imageBuffer, orientation: .up).perform([request])
        return request.results?.lazy.compactMap(\.payloadStringValue).first(where: ScannedCode.isOwn)
    }
}
