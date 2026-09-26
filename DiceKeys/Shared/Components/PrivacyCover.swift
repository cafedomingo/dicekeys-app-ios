//
//  PrivacyCover.swift
//  DiceKeys
//

import SwiftUI

/// Whether the cover belongs on screen.
///
/// `.background` is covered unconditionally: that is when iOS snapshots the app for the
/// switcher, and the snapshot would otherwise show whatever DiceKey or derived secret was
/// on screen, revealed dice included. `.inactive` is covered too, since the sheet over the
/// scene may be anyone's, except in the moment after the user authenticated to us, when the
/// only thing still to happen is iOS dismissing its own Face ID sheet.
func privacyCoverIsVisible(scenePhase: ScenePhase, authenticationJustSucceeded: Bool) -> Bool {
    switch scenePhase {
    case .active: false
    case .inactive: !authenticationJustSucceeded
    default: true
    }
}

/// Hides the screen whenever the scene is not active. The root view and every sheet apply
/// it, because sheets are presented above the root's overlays.
private struct PrivacyCover: ViewModifier {
    @Environment(\.scenePhase) private var scenePhase
    /// Optional because the modifier is applied inside sheets, which inherit the
    /// environment but need not be reached from a context that provides the store.
    @Environment(DiceKeyMemoryStore.self) private var diceKeyMemoryStore: DiceKeyMemoryStore?

    private var isVisible: Bool {
        privacyCoverIsVisible(
            scenePhase: scenePhase,
            authenticationJustSucceeded: diceKeyMemoryStore?.authenticationJustSucceeded ?? false
        )
    }

    func body(content: Content) -> some View {
        content
            .overlay {
                if isVisible {
                    // Appears at once, so the snapshot never catches it half-faded; fades
                    // out on return.
                    PrivacyCoverView()
                        .transition(.asymmetric(insertion: .identity, removal: .opacity))
                }
            }
            .animation(.easeOut(duration: 0.25), value: isVisible)
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
