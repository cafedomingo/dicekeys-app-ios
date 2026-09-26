//
//  TypeYourDiceKeyView.swift
//  DiceKeys
//
//  Created by Kevin Shah on 13/01/21.
//

import SwiftUI

/// Type a DiceKey in by hand, one face at a time.
struct TypeYourDiceKeyView: View {
    let editableDiceKeyState: EditableDiceKeyState
    var onDiceKeyEntered: ((_ diceKey: DiceKey) -> Void)?

    var body: some View {
        VStack(alignment: .center) {
            Spacer()
            DiceKeyView(
                partialFaces: editableDiceKeyState.faces,
                highlightIndexes: Set([editableDiceKeyState.faceSelectedIndex]),
                onFacePressed: { faceIndex in editableDiceKeyState.faceSelectedIndex = faceIndex }
            )
            Spacer()
            DiceKeyboardView(editableDiceKeyState: editableDiceKeyState)
            Spacer()
            PrimaryButton("Done") {
                if let diceKey = editableDiceKeyState.diceKey {
                    onDiceKeyEntered?(diceKey)
                }
            }
            .showIf(editableDiceKeyState.diceKey != nil)
            Spacer()
        }
        .padding()
    }
}

#Preview {
    TypeYourDiceKeyView(editableDiceKeyState: EditableDiceKeyState())
}
