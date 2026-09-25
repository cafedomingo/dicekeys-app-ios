//
//  ActionButtons.swift
//  DiceKeys
//
//  Replaces the hand-drawn `RoundedTextButton`. Standard buttons pick up
//  Liquid Glass from the system; these wrappers only fix the style and size.
//

import SwiftUI

/// The main call to action on a screen.
struct PrimaryButton: View {
    let title: String
    let action: () -> Void

    init(_ title: String, action: @escaping () -> Void) {
        self.title = title
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.title3)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
        }
        .buttonStyle(.glassProminent)
        .controlSize(.large)
    }
}

/// A secondary action shown next to, or instead of, a `PrimaryButton`.
struct SecondaryButton: View {
    let title: String
    let role: ButtonRole?
    let action: () -> Void

    init(_ title: String, role: ButtonRole? = nil, action: @escaping () -> Void) {
        self.title = title
        self.role = role
        self.action = action
    }

    var body: some View {
        Button(title, role: role, action: action)
            .buttonStyle(.glass)
            .controlSize(.large)
    }
}

#Preview {
    VStack(spacing: 16) {
        PrimaryButton("Scan") {}
        SecondaryButton("Cancel", role: .cancel) {}
    }
    .padding()
}
