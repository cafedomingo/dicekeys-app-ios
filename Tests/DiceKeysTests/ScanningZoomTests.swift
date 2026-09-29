//
//  ScanningZoomTests.swift
//  DiceKeysTests
//

import CoreGraphics
import Testing
@testable import DiceKeys

@Suite("Zoom for scanning")
struct ScanningZoomTests {
    private let frame = CGSize(width: 1920, height: 1080)

    @Test("zooms a camera that cannot focus as close as the target asks")
    func zoomsWhenTheTargetIsTooClose() {
        // A 70-degree camera puts a key filling the window about 17 cm away, inside a 20 cm focus
        // limit, so it zooms until that key is 20 cm away.
        let zoom = CameraSession.zoomForScanning(minimumFocusDistance: 200, fieldOfView: 70, frameSize: frame)
        #expect(zoom > 1.1 && zoom < 1.2)
    }

    @Test("leaves a camera that can focus closer than the target at its widest")
    func leavesACloseFocusingCameraAlone() {
        #expect(CameraSession.zoomForScanning(minimumFocusDistance: 100, fieldOfView: 70, frameSize: frame) < 1)
        // A camera with a very wide view puts the target only a few centimeters away.
        #expect(CameraSession.zoomForScanning(minimumFocusDistance: 20, fieldOfView: 110, frameSize: frame) < 1)
    }

    @Test("does not depend on which way the frame is turned")
    func ignoresFrameOrientation() {
        let landscape = CameraSession.zoomForScanning(minimumFocusDistance: 200, fieldOfView: 70, frameSize: frame)
        let portrait = CameraSession.zoomForScanning(minimumFocusDistance: 200, fieldOfView: 70, frameSize: CGSize(width: 1080, height: 1920))
        #expect(landscape == portrait)
    }
}
