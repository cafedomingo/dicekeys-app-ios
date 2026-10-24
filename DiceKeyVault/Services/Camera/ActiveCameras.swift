//
//  ActiveCameras.swift
//  DiceKeyVault
//

import AVFoundation

extension AVCaptureDevice {
    /// Whether the device is a connected video camera we can show a preview for.
    var canBeDisplayed: Bool {
        hasMediaType(.video) && isConnected && !isSuspended
    }
}

/// Enumerates the cameras usable for scanning. Discovery is not free, so callers
/// keep the result rather than asking on every render.
@MainActor
enum ActiveCameras {
    /// On a phone, the back wide-angle camera: the sharpest, and CameraSession zooms it so
    /// the key stays far enough away to focus on. The ultra wide is left out: it sees less
    /// of each die and has to be held closer, and on the phone it scanned far worse.
    ///
    /// On a Mac, every camera: built-in, display, Continuity Camera and USB webcam, none of
    /// which is at the back.
    static func get() -> [AVCaptureDevice] {
        #if targetEnvironment(macCatalyst)
            let session = AVCaptureDevice.DiscoverySession(
                deviceTypes: [.builtInWideAngleCamera, .continuityCamera, .external],
                mediaType: .video,
                position: .unspecified
            )
        #else
            let session = AVCaptureDevice.DiscoverySession(
                deviceTypes: [.builtInWideAngleCamera],
                mediaType: .video,
                position: .back
            )
        #endif
        return session.devices.filter(\.canBeDisplayed)
    }

    /// Requests camera permission if it has not been decided yet.
    static func requestAccessIfNeeded() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            return true
        case .notDetermined:
            return await AVCaptureDevice.requestAccess(for: .video)
        case .denied, .restricted:
            return false
        @unknown default:
            return false
        }
    }
}
