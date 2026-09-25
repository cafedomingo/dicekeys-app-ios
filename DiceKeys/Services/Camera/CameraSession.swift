//
//  CameraSession.swift
//  DiceKeys
//
//  Created by Stuart Schechter on 2020/11/23.
//  Using code from https://github.com/RosayGaspard/SwiftUI-Simple-camera-app/blob/master/SwiftUI-CameraApp/CameraController.swift
//

import AVFoundation
import Foundation

/// Owns the `AVCaptureSession` for scanning, its preview layer, and (on iOS)
/// the `RotationCoordinator` that keeps the preview and the scanned frames
/// level with the horizon. Frames go to `CameraSampleBufferDelegate`.
@MainActor
final class CameraSession {
    enum CameraSessionError: Error {
        case inputsAreInvalid
        case noCamerasAvailable
    }

    let session = AVCaptureSession()
    private let delegate: CameraSampleBufferDelegate
    /// The output whose connection carries the frames; rotated with the preview.
    private var videoOutput: AVCaptureVideoDataOutput?
    private(set) var camera: AVCaptureDevice?
    private(set) var previewLayer: AVCaptureVideoPreviewLayer?
    private var rotationCoordinator: AVCaptureDevice.RotationCoordinator?
    private var rotationObservations: [NSKeyValueObservation] = []

    init(processor: DiceKeyFrameProcessor, onFrame: @escaping @MainActor @Sendable (ScannedFrame) -> Void) {
        self.delegate = CameraSampleBufferDelegate(processor: processor, onFrame: onFrame)
    }

    /// Bumped by every `start` and `stop`; a `start` that finds it changed after an await
    /// was superseded and must not go on to start the session or install a preview.
    private var generation = 0
    /// The last blocking session operation, so the next one waits for it.
    private var lastOperation: Task<Void, Never>?

    /// Configures the session for `camera` and starts it. Configuration and
    /// `startRunning()` happen off the main actor because they block.
    ///
    /// `AVCaptureSession` and `AVCaptureDevice` are not `Sendable` in the SDK, but
    /// Apple's own guidance is to configure and start the session on a background
    /// queue, and `serialized` runs one such operation at a time, so the captures are
    /// marked `nonisolated(unsafe)`.
    func start(camera: AVCaptureDevice) async throws {
        await stop()
        generation += 1
        let generation = generation
        self.camera = camera
        nonisolated(unsafe) let session = self.session
        let delegate = self.delegate
        nonisolated(unsafe) let camera = camera
        let box = OutputBox()
        await serialized {
            do {
                box.output = try Self.configure(session: session, camera: camera, delegate: delegate)
            } catch {
                box.error = error
            }
        }
        if let error = box.error { throw error }
        guard generation == self.generation else { return }
        await serialized { session.startRunning() }
        // A stop() that arrived during startRunning() queued its stopRunning() behind it.
        guard generation == self.generation else { return }
        videoOutput = box.output
        makePreviewLayer(for: camera)
    }

    func stop() async {
        generation += 1
        rotationObservations = []
        rotationCoordinator = nil
        previewLayer?.removeFromSuperlayer()
        previewLayer = nil
        nonisolated(unsafe) let session = self.session
        await serialized {
            if session.isRunning {
                session.stopRunning()
            }
        }
    }

    /// Runs a blocking session operation off the main actor, after every earlier one has
    /// finished, so configuration, `startRunning()` and `stopRunning()` never overlap.
    private func serialized(_ operation: @escaping @Sendable () -> Void) async {
        let previous = lastOperation
        let task = Task.detached(priority: .userInitiated) {
            await previous?.value
            operation()
        }
        lastOperation = task
        await task.value
    }

    @discardableResult
    private nonisolated static func configure(
        session: AVCaptureSession,
        camera: AVCaptureDevice,
        delegate: CameraSampleBufferDelegate
    ) throws -> AVCaptureVideoDataOutput {
        session.beginConfiguration()
        defer { session.commitConfiguration() }

        for input in session.inputs { session.removeInput(input) }
        for output in session.outputs { session.removeOutput(output) }

        do {
            // NOTE - for future MacOS compat, follow this:
            // https://developer.apple.com/documentation/avfoundation/avcapturedevice/1387810-lockforconfiguration
            try camera.lockForConfiguration()
            defer { camera.unlockForConfiguration() }
            if camera.isFocusModeSupported(.continuousAutoFocus) {
                camera.focusMode = .continuousAutoFocus
            }
            if camera.isFocusPointOfInterestSupported {
                // Focus on center
                camera.focusPointOfInterest = CGPoint(x: 0.5, y: 0.5)
            }
            if camera.isAutoFocusRangeRestrictionSupported {
                // Focus close by
                camera.autoFocusRangeRestriction = .near
            }
            if camera.isExposureModeSupported(.continuousAutoExposure) {
                camera.exposureMode = .continuousAutoExposure
            }
        }

        guard let cameraInput = try? AVCaptureDeviceInput(device: camera), session.canAddInput(cameraInput) else {
            throw CameraSessionError.inputsAreInvalid
        }
        session.addInput(cameraInput)

        let videoOutput = AVCaptureVideoDataOutput()
        videoOutput.alwaysDiscardsLateVideoFrames = true
        // The single DispatchQueue in the app: AVFoundation requires a serial queue
        // for sample-buffer delivery.
        videoOutput.setSampleBufferDelegate(delegate, queue: DispatchQueue(label: "com.dicekeys.sampleBuffers"))
        if session.canAddOutput(videoOutput) {
            session.addOutput(videoOutput)
        }
        return videoOutput
    }

    private func makePreviewLayer(for camera: AVCaptureDevice) {
        let previewLayer = AVCaptureVideoPreviewLayer(session: session)
        previewLayer.videoGravity = .resizeAspectFill
        self.previewLayer = previewLayer
        // Front and Mac cameras are mirrored in the preview by default, but the scanner
        // reads the unmirrored frames and the overlay is drawn in frame coordinates, so
        // the preview must show the frames as they are.
        if let connection = previewLayer.connection, connection.isVideoMirroringSupported {
            connection.automaticallyAdjustsVideoMirroring = false
            connection.isVideoMirrored = false
        }

        let coordinator = AVCaptureDevice.RotationCoordinator(device: camera, previewLayer: previewLayer)
        rotationCoordinator = coordinator
        // One angle drives both the preview and the frames. AVFoundation publishes two,
        // and its own documentation warns they differ "in certain combinations of device
        // and interface orientations"; feeding the preview one and the frames the other
        // is what left landscape scans a quarter turn out while portrait looked fine.
        // Which angle is used matters far less than that both get the same one: the
        // overlay is drawn in frame coordinates over the preview, so they have to agree.
        rotationObservations = [
            coordinator.observe(\.videoRotationAngleForHorizonLevelPreview, options: [.initial, .new]) { [weak self] coordinator, _ in
                let angle = coordinator.videoRotationAngleForHorizonLevelPreview
                Task { @MainActor [weak self] in
                    self?.applyPreviewRotation(angle)
                    self?.applyCaptureRotation(angle)
                }
            }
        ]
    }

    private func applyPreviewRotation(_ angle: CGFloat) {
        guard let connection = previewLayer?.connection, connection.isVideoRotationAngleSupported(angle) else { return }
        connection.videoRotationAngle = angle
    }

    /// Rotates the frames by the same angle as the preview. `AVCaptureVideoDataOutput`
    /// physically rotates its buffers, so the scanner and the overlay work in the
    /// coordinates the user is looking at, whatever AVFoundation's angle convention is.
    /// This replaced a hand-written angle-to-`CGImagePropertyOrientation` table that was
    /// only correct in portrait.
    private func applyCaptureRotation(_ angle: CGFloat) {
        guard let connection = videoOutput?.connection(with: .video),
              connection.isVideoRotationAngleSupported(angle) else { return }
        connection.videoRotationAngle = angle
    }
}

/// Carries the configured output, or the error, back from the detached configuration task.
private final class OutputBox: @unchecked Sendable {
    var output: AVCaptureVideoDataOutput?
    var error: (any Error)?
}
