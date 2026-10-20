//
//  PrimaryAction.swift
//  DiceKeys
//

import SwiftUI

extension View {
    /// The one main action on a screen: Liquid Glass tinted `accent` with an `on-accent` label,
    /// in both appearances. The app's tint stays `accent-ink`, which reads as text on light
    /// backgrounds where `accent` doesn't.
    func primaryAction() -> some View {
        buttonStyle(.glassProminent)
            .tint(Color.accent)
            .foregroundStyle(Color.onAccent)
    }
}
