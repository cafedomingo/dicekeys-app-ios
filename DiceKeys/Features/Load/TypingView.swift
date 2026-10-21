//
//  TypingView.swift
//  DiceKeys
//

import DiceKeySpecification
import SwiftUI

/// Each die in three steps, its letter, its digit, then which way is up, so no die is left
/// upright by default. A letter already on another die can't be typed. Once every die is in,
/// Open DiceKey takes the keypad's place; tap a die to redo it. A hardware keyboard types the
/// same way, with an arrow for where the top of the letter points.
struct TypingView: View {
    private static let keyHeight: CGFloat = 40
    private static let keySpacing: CGFloat = 6
    private static let keyFontSize: CGFloat = 22
    private static let letterColumns = 5
    /// The six digits as a phone-style pad filling the letters' space.
    private static let digitColumns = 3
    private static let digitFontSize: CGFloat = 34
    private static var digitKeyHeight: CGFloat {
        let rows = CGFloat(FaceDigits.count / digitColumns)
        return (keypadHeight - (rows - 1) * keySpacing) / rows
    }
    private static let orientationDieSize: CGFloat = 64
    private static var keypadHeight: CGFloat {
        let rows = FaceLetters.count / letterColumns
        return CGFloat(rows) * keyHeight + CGFloat(rows - 1) * keySpacing
    }

    let typed: TypedDiceKey
    let onDone: (DiceKey) -> Void
    @Environment(\.isSceneCaptured) private var isSceneCaptured
    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(spacing: .space4) {
            DiceKeyGrid(faces: typed.faces, concealed: isSceneCaptured, selectedIndex: typed.selectedIndex) {
                typed.select($0)
            }
            HStack {
                Text(prompt).font(.headline)
                Spacer()
                Button("Delete", systemImage: "delete.left", action: typed.backspace)
                    .labelStyle(.iconOnly)
                    .font(.title2)
            }
            Group {
                if isSceneCaptured {
                    Text("Paused while the screen is shared or recorded.").foregroundStyle(.secondary)
                } else if let diceKey = finished {
                    Button {
                        onDone(diceKey)
                    } label: {
                        Label("Open DiceKey", systemImage: "checkmark").frame(maxWidth: .infinity)
                    }
                    .primaryAction()
                    .controlSize(.extraLarge)
                } else {
                    keypad
                }
            }
            .frame(height: Self.keypadHeight, alignment: .top)
        }
        .focusable()
        .focused($isFocused)
        .focusEffectDisabled()
        .onAppear { isFocused = true }
        .onKeyPress(phases: .down, action: handle)
    }

    /// Every die in and none being redone.
    private var finished: DiceKey? { typed.selectedIndex == nil ? typed.diceKey : nil }

    private var prompt: String {
        guard let index = typed.selectedIndex, let step = typed.step else {
            return "All \(DiceKey.faceCount) in · tap a die to redo it"
        }
        let die = "Die \(index + 1)"
        switch step {
        case .letter: return "\(die) · its letter"
        case .digit: return "\(die) · its number"
        case .orientation: return "\(die) · which way is up?"
        }
    }

    @ViewBuilder
    private var keypad: some View {
        switch typed.step {
        case nil:
            EmptyView()
        case .letter:
            keys(columns: Self.letterColumns) {
                ForEach(FaceLetters, id: \.self) { letter in
                    if typed.usedLetters.contains(letter) {
                        usedKey(letter.rawValue)
                    } else {
                        key(letter.rawValue) { typed.enter(letter: letter) }
                    }
                }
            }
        case .digit:
            keys(columns: Self.digitColumns) {
                ForEach(FaceDigits, id: \.self) { digit in
                    key(digit.rawValue, height: Self.digitKeyHeight, fontSize: Self.digitFontSize) {
                        typed.enter(digit: digit)
                    }
                }
            }
        case .orientation:
            HStack {
                ForEach(FaceOrientationLettersTrbl, id: \.self) { orientation in
                    let face = PartialFace(
                        letter: typed.selectedFace?.letter, digit: typed.selectedFace?.digit, orientation: orientation)
                    Button {
                        typed.choose(orientation)
                    } label: {
                        DieView(face: face, size: Self.orientationDieSize).frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(face.spokenDescription)
                }
            }
        }
    }

    private func keys(columns: Int, @ViewBuilder content: () -> some View) -> some View {
        LazyVGrid(
            columns: Array(repeating: GridItem(.flexible(), spacing: Self.keySpacing), count: columns),
            spacing: Self.keySpacing, content: content)
    }

    private func key(
        _ character: String, height: CGFloat = keyHeight, fontSize: CGFloat = keyFontSize,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(character)
                .font(.dice(size: fontSize))
                .frame(maxWidth: .infinity, minHeight: height)
        }
        .buttonStyle(.bordered)
    }

    /// A letter already on another die: struck through on no key at all, so it reads as taken
    /// rather than faint.
    private func usedKey(_ character: String) -> some View {
        Text(character)
            .font(.dice(size: Self.keyFontSize))
            .strikethrough()
            .foregroundStyle(.tertiary)
            .frame(maxWidth: .infinity, minHeight: Self.keyHeight)
            .accessibilityLabel("\(character), on another die")
    }

    /// Return chooses upright, or finishes once every die is in. Shortcuts pass through, and
    /// nothing is typed while the screen is shared.
    private func handle(_ press: KeyPress) -> KeyPress.Result {
        guard press.modifiers.isDisjoint(with: [.command, .control, .option]), !isSceneCaptured else {
            return .ignored
        }
        switch press.key {
        case .delete: typed.backspace()
        case .upArrow: typed.choose(.Top)
        case .rightArrow: typed.choose(.Right)
        case .downArrow: typed.choose(.Bottom)
        case .leftArrow: typed.choose(.Left)
        case .return:
            if let diceKey = finished { onDone(diceKey) } else { typed.choose(.Top) }
        default:
            let character = press.characters.uppercased()
            if let letter = FaceLetter(rawValue: character) {
                typed.enter(letter: letter)
            } else if let digit = FaceDigit(rawValue: character) {
                typed.enter(digit: digit)
            } else {
                return .ignored
            }
        }
        return .handled
    }
}
