//
//  StrengthBar.swift
//  DiceKeys
//

import SwiftUI

/// A bar filled in proportion to a password's bits and colored by its tier.
struct StrengthBar: View {
    let bits: Double

    private var tier: PasswordStrength.Tier { PasswordStrength.tier(bits: bits) }

    private var color: Color {
        switch tier {
        case .weak: return Color.Interface.strengthWeak
        case .fair: return Color.Interface.strengthFair
        case .good: return Color.Interface.strengthGood
        case .strong: return Color.Interface.strengthStrong
        }
    }

    var body: some View {
        Capsule()
            .fill(Color.secondary.opacity(0.25))
            .overlay(alignment: .leading) {
                GeometryReader { geometry in
                    Capsule()
                        .fill(color)
                        .frame(width: geometry.size.width * PasswordStrength.fill(bits: bits))
                }
            }
            .frame(height: 4)
            .accessibilityElement()
            .accessibilityLabel("Strength")
            .accessibilityValue("\(Int(bits)) bits, \(tier)")
    }
}

#Preview {
    VStack(spacing: 12) {
        ForEach([20.0, 39, 45, 55, 70, 121], id: \.self) { StrengthBar(bits: $0) }
    }
    .padding()
}
