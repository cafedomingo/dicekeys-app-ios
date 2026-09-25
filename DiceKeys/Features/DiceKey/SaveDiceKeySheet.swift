//
//  SaveDiceKeySheet.swift
//  DiceKeys
//
//  Created by Stuart Schechter on 2020/11/28.
//

import SwiftUI

/// The half-sheet that lets the user save the DiceKey to (or remove it from)
/// the keychain.
struct SaveDiceKeySheet: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var diceKeyState: UnlockedDiceKeyState

    @State private var presentedError: PresentableError?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    Image("Phonelet")
                        .resizable().scaledToFit()
                        .background(
                            DiceKeyView(diceKey: diceKeyState.diceKey, diceBoxColor: .alexandrasBlue, diePenColor: .alexandrasBlue)
                                .scaleEffect(0.8)
                        )
                        .frame(maxHeight: 220)
                    Toggle(isOn: $diceKeyState.isDiceKeyStored) {
                        Text("Save the DiceKey")
                            .font(.title)
                            .bold()
                            .lineLimit(1)
                            .minimumScaleFactor(0.5)
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        Text("The center die will appear in the home screen.")
                            .font(.title3)
                        Text("The other 24 dice will be encrypted, and your TouchID, FaceID, or PIN will unlock them.")
                            .font(.title3)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding()
            }
            .scrollEdgeEffectStyle(.soft, for: .top)
            .navigationTitle("Save DiceKey")
            .toolbarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .onChange(of: diceKeyState.lastError) { _, error in
            presentedError = error
        }
        .errorAlert($presentedError)
    }
}

#Preview {
    let model = AppModel.preview(diceKey: DiceKey.createFromRandom())
    if let diceKeyState = model.diceKeyMemoryStore.diceKeyState {
        SaveDiceKeySheet(diceKeyState: diceKeyState)
            .appEnvironment(model)
    }
}
