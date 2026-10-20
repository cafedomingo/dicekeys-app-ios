//
//  ScanControls.swift
//  DiceKeys
//
//  The floating controls over the camera preview: camera picker and torch.
//

import AVFoundation
import SwiftUI

struct ScanControls: View {
    let cameras: [AVCaptureDevice]
    @Binding var selectedCameraID: String?

    @Namespace private var glassNamespace
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var torchOn = false

    private var selectedCamera: AVCaptureDevice? {
        cameras.first { $0.uniqueID == selectedCameraID }
    }

    private var hasTorch: Bool {
        return selectedCamera?.hasTorch ?? false
    }

    var body: some View {
        // All controls share one container so their glass blends and morphs.
        GlassEffectContainer(spacing: .space3) {
            HStack(spacing: .space3) {
                if cameras.count > 1 {
                    Menu {
                        Picker("Camera", selection: $selectedCameraID) {
                            ForEach(cameras, id: \.uniqueID) { camera in
                                Text(camera.localizedName).tag(String?.some(camera.uniqueID))
                            }
                        }
                    } label: {
                        Image(systemName: "camera.aperture")
                            .font(.title3)
                            .frame(width: 44, height: 44)
                    }
                    .accessibilityLabel("Choose camera")
                    .modifier(
                        GlassControl(
                            id: "camera", namespace: glassNamespace, reduceTransparency: reduceTransparency,
                            reduceMotion: reduceMotion))
                }
                if hasTorch {
                    Button {
                        toggleTorch()
                    } label: {
                        Image(systemName: torchOn ? "flashlight.on.fill" : "flashlight.off.fill")
                            .font(.title3)
                            .frame(width: 44, height: 44)
                    }
                    .accessibilityLabel(torchOn ? "Turn torch off" : "Turn torch on")
                    .modifier(
                        GlassControl(
                            id: "torch", namespace: glassNamespace, reduceTransparency: reduceTransparency,
                            reduceMotion: reduceMotion))
                }
            }
            .buttonStyle(.plain)
        }
        .padding(.space3)
        .onChange(of: selectedCameraID) { _, _ in
            torchOn = false
        }
    }

    private func toggleTorch() {
        guard let camera = selectedCamera, camera.hasTorch else { return }
        do {
            try camera.lockForConfiguration()
            defer { camera.unlockForConfiguration() }
            camera.torchMode = torchOn ? .off : .on
            torchOn.toggle()
        } catch {
            // The torch is a convenience; failing to toggle it is not worth an alert.
            print("Torch unavailable: \(error)")
        }
    }
}

/// Interactive glass for one floating control, honoring the accessibility
/// settings: a plain material when transparency is reduced, and no morphing
/// between controls when motion is reduced.
private struct GlassControl: ViewModifier {
    let id: String
    let namespace: Namespace.ID
    let reduceTransparency: Bool
    let reduceMotion: Bool

    func body(content: Content) -> some View {
        if reduceTransparency {
            content
                .background(.regularMaterial, in: Capsule())
        } else if reduceMotion {
            content
                .glassEffect(.regular.interactive())
        } else {
            content
                .glassEffect(.regular.interactive())
                .glassEffectID(id, in: namespace)
        }
    }
}

#Preview {
    @Previewable @State var selected: String?
    ZStack {
        Color.camera
        ScanControls(cameras: [], selectedCameraID: $selected)
    }
}
