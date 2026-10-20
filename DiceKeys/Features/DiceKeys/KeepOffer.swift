//
//  KeepOffer.swift
//  DiceKeys
//

import SwiftUI

extension View {
    /// Asks whether to keep a DiceKey just scanned or typed on this device, since one that isn't
    /// kept has to be read again, all 25 dice, each time it locks. Asked every time such a
    /// DiceKey is read, which is rare, so a DiceKey from before the question gets it too.
    func offersToKeep(_ diceKey: Binding<DiceKey?>) -> some View {
        modifier(KeepOffer(diceKey: diceKey))
    }
}

private struct KeepOffer: ViewModifier {
    @Binding var diceKey: DiceKey?

    @Environment(SavedDiceKeys.self) private var saved
    @State private var error: PresentableError?

    func body(content: Content) -> some View {
        content
            .alert(
                "Keep this DiceKey on this device?",
                isPresented: Binding(get: { diceKey != nil }, set: { if !$0 { diceKey = nil } }),
                presenting: diceKey
            ) { diceKey in
                Button("Keep on this device") { keep(diceKey) }
                Button("Not now", role: .cancel) {}
            } message: { _ in
                Text(
                    "Face ID or the passcode unlocks it next time, instead of reading all 25 dice again. It stays in this device's keychain and is never synced or backed up."
                )
            }
            .errorAlert($error)
    }

    private func keep(_ diceKey: DiceKey) {
        do {
            try saved.save(diceKey)
        } catch {
            self.error = PresentableError(title: "Keychain Unavailable", error: error)
        }
    }
}
