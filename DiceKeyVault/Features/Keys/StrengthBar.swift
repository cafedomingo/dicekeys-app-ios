//
//  StrengthBar.swift
//  DiceKeyVault
//

import SwiftUI

/// A passphrase's strength as a bar, exact because every character or word is uniform. No
/// standard scores bits, so the scale is the app's own.
struct StrengthBar: View {
    private static let fullBits = 80.0
    private static let tiers: [(floor: Double, color: Color, name: String)] = [
        (0, Color.strengthWeak, "weak"), (40, Color.strengthFair, "fair"),
        (50, Color.strengthGood, "good"), (60, Color.strengthStrong, "strong")
    ]
    private static let height: CGFloat = 4

    let bits: Double

    private var tier: (floor: Double, color: Color, name: String) {
        Self.tiers.last { bits >= $0.floor } ?? Self.tiers[0]
    }

    var body: some View {
        Capsule()
            .fill(.fill.secondary)
            .overlay(alignment: .leading) {
                GeometryReader { geometry in
                    Capsule()
                        .fill(tier.color)
                        .frame(width: geometry.size.width * min(bits / Self.fullBits, 1))
                }
            }
            .frame(height: Self.height)
            .accessibilityElement()
            .accessibilityLabel("Strength")
            .accessibilityValue("\(Int(bits)) bits, \(tier.name)")
    }
}
