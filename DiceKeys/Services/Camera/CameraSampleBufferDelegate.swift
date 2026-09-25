//
//  CameraSampleBufferDelegate.swift
//  DiceKeys
//
//  Created by Stuart Schechter on 2020/11/23.
//

import AVFoundation
import CoreImage

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
    private let ciContext = CIContext(options: nil)

    init(processor: DiceKeyFrameProcessor, onFrame: @escaping @MainActor @Sendable (ScannedFrame) -> Void) {
        self.processor = processor
        self.onFrame = onFrame
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        // Skip the (expensive) crop when the previous frame is still being scanned.
        guard !processor.isBusy, let imageBuffer = sampleBuffer.imageBuffer else { return }

        // The buffers arrive rotated by AVFoundation (see CameraSession.applyCaptureRotation),
        // so there is nothing left to correct here.
        guard let frame = rgbaCenteredSquare(from: imageBuffer, orientation: .up, context: ciContext) else { return }
        processor.trySubmit(
            rgba: frame.rgba, width: frame.width, height: frame.height,
            onResult: onFrame
        )
    }
}

/// Crops the largest centered square out of a camera frame and returns it as
/// 8-bit RGBA, the format `DiceKeyScanner` expects.
nonisolated func rgbaCenteredSquare(
    from imageBuffer: CVPixelBuffer,
    orientation: CGImagePropertyOrientation,
    context: CIContext
) -> (rgba: Data, width: Int, height: Int)? {
    let ciImage = CIImage(cvPixelBuffer: imageBuffer).oriented(orientation)
    let frameWidth = ciImage.extent.width
    let frameHeight = ciImage.extent.height
    let squareSize = min(frameWidth, frameHeight)
    let centeredSquare = CGRect(
        x: (frameWidth - squareSize) / 2,
        y: (frameHeight - squareSize) / 2,
        width: squareSize,
        height: squareSize
    )
    guard let cgImage = context.createCGImage(ciImage, from: centeredSquare) else { return nil }

    let width = cgImage.width
    let height = cgImage.height
    let bytesPerRow = 4 * width
    var rgba = Data(count: bytesPerRow * height)
    let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)
    let drew = rgba.withUnsafeMutableBytes { rawBuffer -> Bool in
        guard let bitmapContext = CGContext(
            data: rawBuffer.baseAddress,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: bitmapInfo.rawValue
        ) else { return false }
        bitmapContext.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        return true
    }
    guard drew else { return nil }
    return (rgba, width, height)
}
