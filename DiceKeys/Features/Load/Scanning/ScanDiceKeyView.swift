//
//  ScanDiceKeyView.swift
//  DiceKeys
//

import AVFoundation
import SwiftUI

/// The camera preview with the read-faces overlay and floating controls.
/// Calls `onDiceKeyRead` once, when a complete DiceKey has been scanned.
struct ScanDiceKeyView: View {
    let onDiceKeyRead: (_ diceKey: DiceKey) -> Void

    @State private var scanModel = DiceKeyScanModel()
    @State private var cameraAuthorized: Bool?
    @State private var selectedCameraID: String?
    @State private var cameraError: PresentableError?

    /// Discovered once and again when a camera connects or disconnects, not per render:
    /// the body re-evaluates on every scanned frame.
    @State private var cameras: [AVCaptureDevice] = []

    private var selectedCamera: AVCaptureDevice? {
        cameras.first { $0.uniqueID == selectedCameraID }
    }

    var body: some View {
        VStack(alignment: .center, spacing: 0) {
            switch cameraAuthorized {
            case .some(true):
                scanner
                Text("\(scanModel.facesRead) of \(DiceKey.faceCount) dice read")
                    .font(.headline)
                    .monospacedDigit()
                    .padding(.top, .space3)
                Text(
                    scanModel.hasRepeatedLetters
                        ? "Two dice share a letter, so these aren't one DiceKey. Check for a die from another set."
                        : "Hold the box flat, lid off"
                )
                .font(.footnote)
                .foregroundStyle(.secondary)
            case .some(false):
                ContentUnavailableView(
                    "Camera Access Needed",
                    systemImage: "camera",
                    description: Text("Permission to access the camera is required to scan your DiceKey")
                )
            case .none:
                ProgressView()
            }
        }
        .task {
            cameraAuthorized = await ActiveCameras.requestAccessIfNeeded()
            cameras = ActiveCameras.get()
        }
        // The first camera, until one is chosen, and again if the chosen one goes away.
        .onChange(of: cameras) { _, cameras in
            if !cameras.contains(where: { $0.uniqueID == selectedCameraID }) {
                selectedCameraID = cameras.first?.uniqueID
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: AVCaptureDevice.wasConnectedNotification)) { _ in
            cameras = ActiveCameras.get()
        }
        .onReceive(NotificationCenter.default.publisher(for: AVCaptureDevice.wasDisconnectedNotification)) { _ in
            cameras = ActiveCameras.get()
        }
        .onChange(of: scanModel.completedDiceKey) { _, diceKey in
            if let diceKey {
                onDiceKeyRead(diceKey)
            }
        }
        .errorAlert($cameraError)
    }

    private var scanner: some View {
        GeometryReader { reader in
            let size = CGSize(width: reader.size.width, height: reader.size.width)
            ZStack(alignment: .bottom) {
                CameraPreviewView(
                    camera: selectedCamera,
                    size: size,
                    onFrame: { [scanModel] frame in scanModel.apply(frame) },
                    onFailure: { error in
                        cameraError = PresentableError(title: "Camera Unavailable", error: error)
                    }
                )
                FacesReadOverlay(
                    renderedSize: size,
                    dice: scanModel.dice,
                    imageFrameSize: scanModel.imageFrameSize
                )
                ScanControls(cameras: cameras, selectedCameraID: $selectedCameraID)
            }
            .frame(width: size.width, height: size.height)
        }
        .aspectRatio(1, contentMode: .fit)
        .background(Color.camera)
        .clipShape(RoundedRectangle(cornerRadius: .radiusMd))
        .padding(.vertical, .space1)
    }
}

#Preview {
    ScanDiceKeyView(onDiceKeyRead: { _ in })
}
