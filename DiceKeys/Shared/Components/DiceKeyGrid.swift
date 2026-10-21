//
//  DiceKeyGrid.swift
//  DiceKeys
//
//  A DiceKey is only ever drawn as a 5×5 grid of its faces: letter and digit in the face
//  printed on the dice, turned to the die's orientation, with a bar beneath like the real die.
//

import DiceKeySpecification
import SwiftUI

extension Font {
    /// Inconsolata Bold, the face printed on the dice, bundled in `fonts/`; used for nothing else.
    static func dice(size: CGFloat) -> Font { .custom(diceFontName, size: size) }
    private static let diceFontName = "Inconsolata-Bold"
}

/// One die: its glyphs turned to its orientation, or blank when concealed or not yet entered.
struct DieView: View {
    /// Side lengths, in points, of each place a die is drawn.
    enum Size {
        static let grid: CGFloat = 44
        static let header: CGFloat = 52
        static let row: CGFloat = 28
    }

    /// Proportions of the side length.
    private enum Ratio {
        static let corner: CGFloat = 0.18
        static let glyph: CGFloat = 0.43
        static let gap: CGFloat = 0.04
        static let barWidth: CGFloat = 0.32
        static let barHeight: CGFloat = 0.045
    }
    private static let minimumBarHeight: CGFloat = 1.5
    private static let shadowOpacity = 0.25
    private static let shadowRadius: CGFloat = 1
    private static let shadowOffset: CGFloat = 1

    static func spacing(for size: CGFloat) -> CGFloat { size * Ratio.corner }

    let face: PartialFace
    var concealed = false
    var size = Size.grid

    var body: some View {
        RoundedRectangle(cornerRadius: size * Ratio.corner)
            .fill(Color.dieFace)
            .shadow(
                color: Color.onDie.opacity(Self.shadowOpacity), radius: Self.shadowRadius, y: Self.shadowOffset
            )
            .frame(width: size, height: size)
            .overlay {
                if !concealed, let letter = face.letter {
                    VStack(spacing: size * Ratio.gap) {
                        Text(letter.rawValue + (face.digit?.rawValue ?? " "))
                            .font(.dice(size: size * Ratio.glyph))
                        Capsule().frame(
                            width: size * Ratio.barWidth, height: max(Self.minimumBarHeight, size * Ratio.barHeight))
                    }
                    .foregroundStyle(Color.onDie)
                    .rotationEffect(.degrees(face.orientation?.clockwiseDegrees ?? 0))
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(concealed ? "Concealed" : face.spokenDescription)
    }
}

/// The grid sits in a dark box, as the dice do.
struct DiceKeyGrid: View {
    private static let side = 5
    private static let selectionLineWidth: CGFloat = 3
    private static let boxPaddingRatio: CGFloat = 0.3
    private static let boxCornerRatio: CGFloat = 0.4

    let faces: [PartialFace]
    var concealed = false
    var dieSize = DieView.Size.grid
    var selectedIndex: Int?
    var onSelect: ((Int) -> Void)?

    var body: some View {
        let spacing = DieView.spacing(for: dieSize)
        Grid(horizontalSpacing: spacing, verticalSpacing: spacing) {
            ForEach(0..<Self.side, id: \.self) { row in
                GridRow {
                    ForEach(0..<Self.side, id: \.self) { column in
                        die(at: row * Self.side + column)
                    }
                }
            }
        }
        .padding(dieSize * Self.boxPaddingRatio)
        .background(Color.dieBox, in: .rect(cornerRadius: dieSize * Self.boxCornerRatio))
        .accessibilityElement(children: concealed ? .ignore : .contain)
        .accessibilityLabel(concealed ? "DiceKey, concealed" : "DiceKey")
    }

    @ViewBuilder
    private func die(at index: Int) -> some View {
        let die = DieView(face: faces[index], concealed: concealed, size: dieSize)
            .overlay {
                if index == selectedIndex {
                    RoundedRectangle(cornerRadius: DieView.spacing(for: dieSize)).strokeBorder(
                        Color.accent, lineWidth: Self.selectionLineWidth)
                }
            }
        if let onSelect {
            Button {
                onSelect(index)
            } label: {
                die
            }.buttonStyle(.plain)
        } else {
            die
        }
    }
}

extension DiceKeyGrid {
    init(diceKey: DiceKey, concealed: Bool = false) {
        self.init(faces: diceKey.faces.map(PartialFace.init), concealed: concealed)
    }
}

/// A DiceKey's center die: how it is recognized in lists, whatever it is named.
struct DiceAvatar: View {
    let centerFace: String
    var size = DieView.Size.row

    var body: some View {
        DieView(face: (try? Face(humanReadableForm: centerFace)).map(PartialFace.init) ?? PartialFace(), size: size)
    }
}

extension PartialFace {
    var spokenDescription: String {
        guard let letter else { return "empty" }
        return [letter.rawValue + (digit?.rawValue ?? ""), orientation?.spokenDirection].compactMap(\.self)
            .joined(separator: ", ")
    }
}

#Preview {
    VStack(spacing: .space6) {
        DiceKeyGrid(diceKey: .example)
        DiceKeyGrid(diceKey: .example, concealed: true)
        DiceAvatar(centerFace: DiceKey.example.centerFace.humanReadableForm, size: DieView.Size.header)
    }
    .padding()
}
