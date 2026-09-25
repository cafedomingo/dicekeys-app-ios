//
//  ScanControls.swift
//  DiceKeys
//
//  The floating controls over the camera preview: camera picker, torch, cancel.
//

import SwiftUI
import AVFoundation

struct ScanControls: View {
    let cameras: [AVCaptureDevice]
    @Binding var selectedCameraID: String?
    let onCancel: (() -> Void)?

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
        GlassEffectContainer(spacing: 12) {
            HStack(spacing: 12) {
                if cameras.count > 1 {
                    Menu {
                        ForEach(cameras, id: \.uniqueID) { camera in
                            Button(camera.localizedName) {
                                selectedCameraID = camera.uniqueID
                            }
                        }
                    } label: {
                        Image(systemName: "camera.rotate")
                            .font(.title3)
                            .frame(width: 44, height: 44)
                    }
                    .accessibilityLabel("Choose camera")
                    .modifier(GlassControl(id: "camera", namespace: glassNamespace, reduceTransparency: reduceTransparency, reduceMotion: reduceMotion))
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
                    .modifier(GlassControl(id: "torch", namespace: glassNamespace, reduceTransparency: reduceTransparency, reduceMotion: reduceMotion))
                }
                if let onCancel {
                    Button("Cancel", role: .cancel, action: onCancel)
                        .font(.body.weight(.medium))
                        .padding(.horizontal, 16)
                        .frame(height: 44)
                        .modifier(GlassControl(id: "cancel", namespace: glassNamespace, reduceTransparency: reduceTransparency, reduceMotion: reduceMotion))
                }
            }
            .buttonStyle(.plain)
        }
        .padding(12)
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

/// Interactive glass for one floating control, honouring the accessibility
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
    @Previewable @State var selected: String? = nil
    ZStack {
        Color.gray
        ScanControls(cameras: [], selectedCameraID: $selected, onCancel: {})
    }
}
