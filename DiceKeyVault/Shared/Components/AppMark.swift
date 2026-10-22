//
//  AppMark.swift
//  DiceKeyVault
//

import SwiftUI

/// The app icon's grid, drawn from the color tokens so it follows them: 25 dice showing only
/// their bars, each turned as on the icon.
struct AppMark: View {
    static let coverSide: CGFloat = 72
    static let columns = 5
    /// The gap between dice, as a proportion of the side.
    private static let gapRatio: CGFloat = 0.035

    /// Proportions of a die's side.
    enum DieRatio {
        static let corner: CGFloat = 0.16
        static let barLength: CGFloat = 0.34
        static let barThickness: CGFloat = 0.08
        static let barOffset: CGFloat = 0.25
    }

    /// Each die's clockwise turn in degrees, in reading order, as on the icon. An upright
    /// die has its bar at the bottom.
    static let turns: [Double] = [
        180, 90, 0, 270, 180,
        270, 90, 0, 0, 180,
        90, 270, 180, 0, 270,
        90, 180, 270, 0, 90,
        0, 180, 270, 90, 180
    ]

    var side = coverSide

    var body: some View {
        let gap = side * Self.gapRatio
        let die = (side - CGFloat(Self.columns - 1) * gap) / CGFloat(Self.columns)
        Grid(horizontalSpacing: gap, verticalSpacing: gap) {
            ForEach(0..<Self.columns, id: \.self) { row in
                GridRow {
                    ForEach(0..<Self.columns, id: \.self) { column in
                        RoundedRectangle(cornerRadius: die * DieRatio.corner)
                            .fill(Color.accent)
                            .overlay {
                                Capsule()
                                    .fill(Color.onAccent)
                                    .frame(width: die * DieRatio.barLength, height: die * DieRatio.barThickness)
                                    .offset(y: die * DieRatio.barOffset)
                            }
                            .frame(width: die, height: die)
                            .rotationEffect(.degrees(Self.turns[row * Self.columns + column]))
                    }
                }
            }
        }
        .accessibilityHidden(true)
    }
}

#Preview {
    AppMark()
}
