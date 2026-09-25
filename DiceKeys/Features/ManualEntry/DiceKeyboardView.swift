//
//  DiceKeyboardView.swift
//  DiceKeys
//
//  Created by Kevin Shah on 16/01/21.
//

import SwiftUI

private struct KeyboardKey<Content: View>: View {
    let size: CGSize
    let withBackground: Bool
    let action: () -> Void
    let label: () -> Content

    var body: some View {
        Button(action: action) {
            label()
                .frame(width: size.width * 0.95, height: size.height * 0.95)
                .clipped()
                .background(withBackground ? Color.gray : Color.clear)
                .padding(.horizontal, size.width * 0.025)
                .padding(.vertical, size.height * 0.025)
        }
        .buttonStyle(.plain)
    }
}

private struct CharacterKey: View {
    let size: CGSize
    let editableDiceKeyState: EditableDiceKeyState
    let char: Character

    var body: some View {
        KeyboardKey(size: size, withBackground: true, action: { editableDiceKeyState.keyDown(char: char) }) {
            Text(String(char))
                .font(.system(size: 256, design: .monospaced))
                .padding(.top, 2)
                .padding(.bottom, 2)
                .foregroundStyle(.white)
                .scaledToFit()
                .minimumScaleFactor(0.01)
                .lineLimit(1)
        }
    }
}

private struct ImageKey: View {
    let size: CGSize
    let action: () -> Void
    let image: Image

    var body: some View {
        KeyboardKey(size: size, withBackground: false, action: action) {
            image
                .resizable()
                .padding(2)
                .aspectRatio(contentMode: .fit)
                .foregroundStyle(Color.accentColor)
        }
    }
}

/// An on-screen keyboard for entering dice.
struct DiceKeyboardView: View {
    let editableDiceKeyState: EditableDiceKeyState

    private let fractionalSpaceBetween: CGFloat = 0.1
    private let columns: Int = 9
    private let rows: Int = 4

    @State private var bounds: CGSize = CGSize(width: 1, height: 1)
    private var width: CGFloat { bounds.width / CGFloat(columns) }
    private var height: CGFloat { min(bounds.height, width / 1.2) }
    private var padding: CGFloat { fractionalSpaceBetween * width / 2 }
    private var buttonSize: CGSize { CGSize(width: width - 2 * padding, height: height - 2 * padding) }
    private var left: CGFloat { ((1 - CGFloat(columns)) / 2) * width }
    private var top: CGFloat { ((1 - CGFloat(rows)) / 2) * height }

    private func buttonOffset(x: Int, y: Int) -> CGSize {
        CGSize(width: left + CGFloat(x) * width, height: top + CGFloat(y) * height)
    }

    private var showLetterKeys: Bool {
        editableDiceKeyState.faceSelected.letter == nil || editableDiceKeyState.faceSelected.digit != nil
    }

    var body: some View {
        CalculateBounds(bounds: $bounds) {
            ZStack(alignment: .center) {
                ImageKey(size: buttonSize, action: { editableDiceKeyState.rotateLeft() }, image: Image(systemName: "rotate.left"))
                    .offset(buttonOffset(x: 0, y: 0))
                ImageKey(size: buttonSize, action: { editableDiceKeyState.rotateRight() }, image: Image(systemName: "rotate.right"))
                    .offset(buttonOffset(x: 1, y: 0))
                ImageKey(size: buttonSize, action: { editableDiceKeyState.backspace() }, image: Image(systemName: "delete.left.fill"))
                    .offset(buttonOffset(x: columns - 1, y: 0))
                ForEach(Array(FaceLetters.enumerated()), id: \.offset) { faceLetterIndex, faceLetter in
                    if let char = faceLetter.rawValue.first {
                        CharacterKey(size: buttonSize, editableDiceKeyState: editableDiceKeyState, char: char)
                            .offset(buttonOffset(x: faceLetterIndex % columns, y: 1 + faceLetterIndex / columns))
                            .showIf(showLetterKeys)
                    }
                }
                ForEach(Array(FaceDigits.enumerated()), id: \.offset) { faceDigitIndex, faceDigit in
                    if let char = faceDigit.rawValue.first {
                        CharacterKey(size: buttonSize, editableDiceKeyState: editableDiceKeyState, char: char)
                            .offset(buttonOffset(x: faceDigitIndex, y: 1))
                            .hideIf(showLetterKeys)
                    }
                }
            }
            .frame(width: width * CGFloat(columns), height: height * CGFloat(rows))
        }
        .aspectRatio(CGFloat(columns) / CGFloat(rows), contentMode: .fit)
    }
}

#Preview {
    DiceKeyboardView(editableDiceKeyState: EditableDiceKeyState())
}
