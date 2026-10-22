//
//  Backdrop.swift
//  DiceKeyVault
//

import SwiftUI

extension View {
    /// The app's ground behind lists and forms: `bg`, with faint dice that fade out from the
    /// top right corner. A sidebar beside a detail column passes `dice: false`, so the dice
    /// are drawn once, in the screen's corner; it can't tell for itself, since a sidebar is
    /// compact width either way.
    func appBackdrop(dice: Bool = true) -> some View {
        scrollContentBackground(.hidden)
            .background {
                ZStack {
                    Color.bg
                    if dice { CornerDice() }
                }
                .ignoresSafeArea()
            }
    }
}

/// Outlined dice with their bars, turned as on the app icon, on a grid tilted from the top
/// right corner. Each is fainter the farther it is from the corner, until none is drawn.
/// Increase Contrast leaves them out.
private struct CornerDice: View {
    private static let side: CGFloat = 50
    private static let pitch: CGFloat = 62
    private static let tilt = Angle.degrees(-15)
    /// How far from the corner the dice reach before they have faded out.
    private static let reach: CGFloat = 460
    private static let lineWidth: CGFloat = 1.2
    /// Opacity of the outline and the bar at the corner.
    private static let opacity = (light: (outline: 0.10, bar: 0.16), dark: (outline: 0.12, bar: 0.18))

    private static let outline = Path(
        roundedRect: CGRect(x: -side / 2, y: -side / 2, width: side, height: side),
        cornerRadius: side * AppMark.DieRatio.corner)
    private static let bar: Path = {
        let length = side * AppMark.DieRatio.barLength
        let thickness = side * AppMark.DieRatio.barThickness
        return Path(
            roundedRect: CGRect(
                x: -length / 2, y: side * AppMark.DieRatio.barOffset - thickness / 2, width: length,
                height: thickness),
            cornerRadius: thickness / 2)
    }()

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        if contrast == .standard {
            Canvas { context, size in
                let opacity = colorScheme == .dark ? Self.opacity.dark : Self.opacity.light
                let span = Int((Self.reach / Self.pitch).rounded(.up))
                context.translateBy(x: size.width, y: 0)
                context.rotate(by: Self.tilt)
                for row in -span...span {
                    for column in -span...0 {
                        let x = (CGFloat(column) - 0.5) * Self.pitch
                        let y = (CGFloat(row) + 0.5) * Self.pitch
                        let fade = 1 - hypot(x, y) / Self.reach
                        guard fade > 0 else { continue }
                        var die = context
                        die.translateBy(x: x, y: y)
                        die.stroke(
                            Self.outline, with: .color(.primary.opacity(opacity.outline * fade)),
                            lineWidth: Self.lineWidth)
                        die.rotate(by: turn(row: row, column: column))
                        die.fill(Self.bar, with: .color(.primary.opacity(opacity.bar * fade)))
                    }
                }
            }
            .accessibilityHidden(true)
        }
    }

    private func turn(row: Int, column: Int) -> Angle {
        let columns = AppMark.columns
        let index = (row % columns + columns) % columns * columns + (column % columns + columns) % columns
        return .degrees(AppMark.turns[index])
    }
}
