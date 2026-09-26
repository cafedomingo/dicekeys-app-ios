//
//  PrivacyCover.swift
//  DiceKeys
//

import SwiftUI

/// Whether the cover belongs on screen.
///
/// Only when backgrounded. UIKit snapshots the scene for the app switcher immediately after
/// `sceneDidEnterBackground` returns, which is the one moment the screen is captured into
/// something that outlives the user looking at it.
///
/// Deliberately not "whenever the scene is not active". Resigning active also happens for
/// the app switcher gesture, Control Center, Notification Center and system alerts, the Face
/// ID prompt among them, and iOS hands `.active` back as much as a second after the last of
/// those visibly closes. Covering for all of them means the screen stays hidden long after
/// there is anything to hide it from. Apple's QA1838 names `didEnterBackground` as the right
/// moment, and Wallet behaves this way: card details stay visible in the app switcher
/// gesture and are hidden once the app is actually backgrounded.
///
/// The cost, accepted knowingly: revealed dice are visible behind the Face ID sheet, under
/// Control Center, and in a screenshot the user takes themselves. In each the user is present
/// and could see the screen anyway.
func privacyCoverIsVisible(scenePhase: ScenePhase) -> Bool {
    scenePhase == .background
}

/// Hides the screen while the app is backgrounded. The root view and every sheet apply it,
/// because sheets are presented above the root's overlays.
private struct PrivacyCover: ViewModifier {
    @Environment(\.scenePhase) private var scenePhase

    func body(content: Content) -> some View {
        content
            .overlay {
                if privacyCoverIsVisible(scenePhase: scenePhase) {
                    // Inserted without animation: the snapshot is taken as soon as
                    // `didEnterBackground` returns and will not wait for one to finish.
                    PrivacyCoverView()
                        .transition(.asymmetric(insertion: .identity, removal: .opacity))
                }
            }
            .animation(.easeOut(duration: 0.25), value: scenePhase == .background)
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
