//
//  ScanDiceKeyView.swift
//  DiceKeys
//
//  Created by Stuart Schechter on 2020/11/24.
//

import SwiftUI
import AVFoundation

/// The camera preview with the read-faces overlay and floating controls.
/// Calls `onDiceKeyRead` once, when a complete DiceKey has been scanned.
struct ScanDiceKeyView: View {
    var stickers: Bool = false
    let onDiceKeyRead: (_ diceKey: DiceKey) -> Void
    var onCancel: (() -> Void)?

    @State private var scanModel = DiceKeyScanModel()
    @State private var cameraAuthorized: Bool?
    @State private var selectedCameraID: String?
    @State private var cameraError: PresentableError?

    /// Discovered once and again when a camera connects or disconnects, not per render:
    /// the body re-evaluates on every scanned frame.
    @State private var cameras: [AVCaptureDevice] = []

    private var selectedCamera: AVCaptureDevice? {
        if let camera = cameras.first(where: { $0.uniqueID == selectedCameraID }), camera.canBeDisplayed {
            return camera
        }
        return cameras.first
    }

    var body: some View {
        VStack(alignment: .center, spacing: 0) {
            switch cameraAuthorized {
            case .some(true):
                Text("Line up the \(stickers ? "stickers" : "dice") with the squares, then hold steady.")
                    .font(.title2)
                scanner
                Text("\(scanModel.frameCount) frames processed")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.top, 3)
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
            if selectedCameraID == nil {
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
                ScanControls(cameras: cameras, selectedCameraID: $selectedCameraID, onCancel: onCancel)
            }
            .frame(width: size.width, height: size.height)
        }
        .aspectRatio(1, contentMode: .fit)
        .background(Color.Camera.backdrop)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.Interface.objectEdge, lineWidth: 1))
        .padding(.vertical, 5)
    }
}

#Preview {
    ScanDiceKeyView(onDiceKeyRead: { _ in })
}
