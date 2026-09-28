//
//  PrivacyCover.swift
//  DiceKeys
//

import SwiftUI

/// The cover itself: the app icon's blues behind a Liquid Glass tile with the DiceKey
/// mark. Opaque on purpose: a blur of the screen underneath can still show the shape of
/// a password or QR code in the snapshot.
struct PrivacyCoverView: View {
    /// A diagonal of highlight through the body, shadow in the other two corners. Each role
    /// has its own value per appearance in the catalog.
    private static let meshColors: [Color] = [
        Color.Brand.coverHighlight, Color.Brand.coverBody, Color.Brand.coverShadow,
        Color.Brand.coverBody, Color.Brand.coverHighlight, Color.Brand.coverBody,
        Color.Brand.coverShadow, Color.Brand.coverBody, Color.Brand.coverHighlight
    ]

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
                colors: Self.meshColors
            )
            .ignoresSafeArea()

            VStack(spacing: 20) {
                Image("DiceKey Icon")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 64, height: 64)
                    .foregroundStyle(Color.Brand.coverForeground)
                    .padding(28)
                    .glassEffect(.regular, in: .rect(cornerRadius: 32))
                Text("DiceKeys")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(Color.Brand.coverForeground)
            }
        }
        .accessibilityHidden(true)
    }
}

#Preview("Light") {
    PrivacyCoverView()
}

#Preview("Dark") {
    PrivacyCoverView()
        .preferredColorScheme(.dark)
}
