//
//  CameraPreviewView.swift
//  DiceKeys
//
//  Created by Stuart Schechter on 2020/11/19.
//

import SwiftUI
import AVFoundation

/// Hosts the camera preview layer for `camera` and feeds frames to `onFrame`.
/// The `CameraSession` lives in the coordinator for the lifetime of the view.
struct CameraPreviewView {
    let camera: AVCaptureDevice?
    let size: CGSize
    let processor: DiceKeyFrameProcessor
    let onFrame: @MainActor @Sendable (ScannedFrame) -> Void
    /// Called when the session cannot start, so the screen can say so rather than
    /// showing a black rectangle with no explanation.
    var onFailure: (@MainActor @Sendable (any Error) -> Void)? = nil

    @MainActor
    final class Coordinator {
        let session: CameraSession
        private(set) var currentCameraID: String?
        private var startTask: Task<Void, Never>?
        var onFailure: (@MainActor @Sendable (any Error) -> Void)?

        init(processor: DiceKeyFrameProcessor, onFrame: @escaping @MainActor @Sendable (ScannedFrame) -> Void) {
            session = CameraSession(processor: processor, onFrame: onFrame)
        }

        func update(camera: AVCaptureDevice?, in view: UIView, size: CGSize) {
            if camera?.uniqueID != currentCameraID {
                currentCameraID = camera?.uniqueID
                startTask?.cancel()
                startTask = Task { [session] in
                    guard let camera else {
                        await session.stop()
                        return
                    }
                    do {
                        try await session.start(camera: camera)
                    } catch {
                        self.currentCameraID = nil  // so a retry re-attempts this camera
                        self.onFailure?(error)
                        return
                    }
                    guard !Task.isCancelled, let previewLayer = session.previewLayer else { return }
                    view.layer.insertSublayer(previewLayer, at: 0)
                    layout(previewLayer, size: size)
                }
            }
            if let previewLayer = session.previewLayer {
                layout(previewLayer, size: size)
            }
        }

        private func layout(_ layer: CALayer, size: CGSize) {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            layer.frame = CGRect(origin: .zero, size: size)
            CATransaction.commit()
        }

        func tearDown() {
            startTask?.cancel()
            let session = session
            Task { await session.stop() }
        }
    }

    @MainActor
    func makeCoordinator() -> Coordinator {
        let coordinator = Coordinator(processor: processor, onFrame: onFrame)
        coordinator.onFailure = onFailure
        return coordinator
    }
}

extension CameraPreviewView: UIViewRepresentable {
    func makeUIView(context: Context) -> UIView {
        let view = UIView(frame: CGRect(origin: .zero, size: size))
        view.backgroundColor = .black
        view.clipsToBounds = true
        context.coordinator.update(camera: camera, in: view, size: size)
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        context.coordinator.update(camera: camera, in: uiView, size: size)
    }

    static func dismantleUIView(_ uiView: UIView, coordinator: Coordinator) {
        coordinator.tearDown()
    }
}
