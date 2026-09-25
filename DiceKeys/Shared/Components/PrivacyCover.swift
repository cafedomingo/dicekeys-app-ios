//
//  PrivacyCover.swift
//  DiceKeys
//

import SwiftUI

/// Hides the screen whenever the scene is not active. iOS snapshots the app for the app
/// switcher as it leaves the foreground, and that snapshot would otherwise show whatever
/// DiceKey or derived secret was on screen, even after the key expires. The root view and
/// every sheet apply it, because sheets are presented above the root's overlays.
private struct PrivacyCover: ViewModifier {
    @Environment(\.scenePhase) private var scenePhase

    func body(content: Content) -> some View {
        content
            .overlay {
                if scenePhase != .active {
                    // Appears at once, so the snapshot never catches it half-faded; fades
                    // out on return.
                    PrivacyCoverView()
                        .transition(.asymmetric(insertion: .identity, removal: .opacity))
                }
            }
            .animation(.easeOut(duration: 0.25), value: scenePhase == .active)
    }
}

/// The cover itself: the app icon's blues behind a Liquid Glass tile with the DiceKey
/// mark. Opaque on purpose: a blur of the screen underneath can still show the shape of
/// a password or QR code in the snapshot.
struct PrivacyCoverView: View {
    @Environment(\.colorScheme) private var colorScheme

    private static let iconBlue = Color(red: 52 / 255, green: 65 / 255, blue: 141 / 255)
    private static let iconBlueLight = Color(red: 99 / 255, green: 116 / 255, blue: 204 / 255)
    private static let navy = Color(red: 22 / 255, green: 28 / 255, blue: 72 / 255)
    private static let midnight = Color(red: 10 / 255, green: 12 / 255, blue: 34 / 255)

    private var colors: [Color] {
        colorScheme == .dark
            ? [Self.iconBlue, Self.navy, Self.midnight,
               Self.navy, Self.iconBlue, Self.navy,
               Self.midnight, Self.navy, Self.iconBlue]
            : [Self.iconBlueLight, Self.iconBlue, Self.navy,
               Self.iconBlue, Self.iconBlueLight, Self.iconBlue,
               Self.navy, Self.iconBlue, Self.iconBlueLight]
    }

    var body: some View {
        ZStack {
            MeshGradient(
                width: 3,
                height: 3,
                points: [
                    [0, 0], [0.5, 0], [1, 0],
                    [0, 0.5], [0.6, 0.4], [1, 0.5],
                    [0, 1], [0.5, 1], [1, 1]
                ],
                colors: colors
            )
            .ignoresSafeArea()

            VStack(spacing: 20) {
                Image("DiceKey Icon")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 64, height: 64)
                    .foregroundStyle(.white)
                    .padding(28)
                    .glassEffect(.regular, in: .rect(cornerRadius: 32))
                Text("DiceKeys")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(.white)
            }
        }
        .accessibilityHidden(true)
    }
}

extension View {
    func privacyCover() -> some View {
        modifier(PrivacyCover())
    }
}

#Preview("Light") {
    PrivacyCoverView()
}

#Preview("Dark") {
    PrivacyCoverView()
        .preferredColorScheme(.dark)
}
