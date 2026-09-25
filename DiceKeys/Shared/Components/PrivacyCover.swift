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
        content.overlay {
            if scenePhase != .active {
                ZStack {
                    Rectangle().fill(.background)
                    Image("DiceKey Icon")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 96, height: 96)
                        .accessibilityHidden(true)
                }
                .ignoresSafeArea()
            }
        }
    }
}

extension View {
    func privacyCover() -> some View {
        modifier(PrivacyCover())
    }
}
