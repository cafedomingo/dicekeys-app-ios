//
//  StrengthBar.swift
//  DiceKeys
//

import SwiftUI

/// Four capsules, filled to the zxcvbn band: red through orange and yellow to green.
struct StrengthBar: View {
    let band: PasswordStrength.Band

    private var color: Color {
        switch band {
        case .tooGuessable, .veryGuessable: return Color.Interface.strengthWeak
        case .somewhatGuessable: return Color.Interface.strengthFair
        case .safelyUnguessable: return Color.Interface.strengthGood
        case .veryUnguessable: return Color.Interface.strengthStrong
        }
    }

    var body: some View {
        HStack(spacing: 4) {
            ForEach(1...4, id: \.self) { segment in
                Capsule()
                    .fill(segment <= band.rawValue ? color : Color.secondary.opacity(0.25))
                    .frame(height: 4)
            }
        }
        .accessibilityElement()
        .accessibilityLabel("Strength: \(band.label)")
    }
}

#Preview {
    VStack(spacing: 12) {
        ForEach(PasswordStrength.Band.allCases, id: \.rawValue) { StrengthBar(band: $0) }
    }
    .padding()
}
