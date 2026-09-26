//
//  ActiveCameras.swift
//  DiceKeys
//
//  Created by Stuart Schechter on 2021/01/20.
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
    static func get() -> [AVCaptureDevice] {
        // Back cameras first: on a phone that is the one to scan with. A Mac running
        // the app as Designed for iPad has no back camera, so fall back to whatever
        // video device there is (built-in, Continuity Camera, external webcam).
        let back = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInUltraWideCamera, .builtInWideAngleCamera],
            mediaType: .video,
            position: .back
        ).devices.filter(\.canBeDisplayed)
        if !back.isEmpty {
            return back
        }
        return AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInWideAngleCamera, .continuityCamera, .external],
            mediaType: .video,
            position: .unspecified
        ).devices.filter(\.canBeDisplayed)
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
