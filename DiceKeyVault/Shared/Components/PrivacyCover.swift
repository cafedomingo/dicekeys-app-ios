//
//  PrivacyCover.swift
//  DiceKeyVault
//

import SwiftUI

/// What the app switcher shows instead of the screen. Opaque on purpose: a blur of the
/// screen underneath can still show the shape of a secret in the snapshot.
struct PrivacyCoverView: View {
    var body: some View {
        Rectangle()
            .fill(.background)
            .overlay {
                VStack(spacing: .space4) {
                    AppMark()
                    Text(AppInfo.name)
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }
            .ignoresSafeArea()
            .accessibilityHidden(true)
    }
}

#Preview {
    PrivacyCoverView()
}
