//
//  LoadDiceKeyScreen.swift
//  DiceKeys
//
//  Created by Stuart Schechter on 2021/01/25.
//

import SwiftUI

enum LoadDiceKeyEntryMethod {
    case byCamera
    case manual
}

/// Scan a DiceKey with the camera, or type it in by hand.
struct LoadDiceKeyScreen: View {
    private enum EntryMode {
        case camera
        case manual
    }

    @State private var entryMode: EntryMode = .camera

    // Holding the manual-entry state here means that switching between the
    // camera and typing does not lose the dice the user has already entered.
    @State private var editableDiceKeyState = EditableDiceKeyState()

    let onDiceKeyLoaded: (_ diceKey: DiceKey, _ entryMethod: LoadDiceKeyEntryMethod) -> Void

    var body: some View {
        VStack(alignment: .center, spacing: 12) {
            switch entryMode {
            case .camera:
                ScanDiceKeyView(onDiceKeyRead: { diceKey in onDiceKeyLoaded(diceKey, .byCamera) })
                Button("Enter the DiceKey by Hand") { entryMode = .manual }
                    .buttonStyle(.glass)
            case .manual:
                TypeYourDiceKeyView(
                    editableDiceKeyState: editableDiceKeyState,
                    onDiceKeyEntered: { diceKey in onDiceKeyLoaded(diceKey, .manual) }
                )
                Button("Scan the DiceKey with my Camera") { entryMode = .camera }
                    .buttonStyle(.glass)
                    .padding(.bottom, 10)
            }
        }
        .padding(.horizontal)
        .navigationTitle("Load your DiceKey")
        .toolbarTitleDisplayMode(.inline)
    }
}

#Preview {
    NavigationStack {
        LoadDiceKeyScreen(onDiceKeyLoaded: { diceKey, _ in print("DiceKey loaded: \(diceKey.toHumanReadableForm())") })
    }
    .appEnvironment(AppModel.preview())
}
