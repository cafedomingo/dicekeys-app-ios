//
//  UnlockButton.swift
//  DiceKeys
//

import SwiftUI

/// Unlocks a DiceKey kept on this device, behind Face ID, Touch ID or the passcode.
struct UnlockButton: View {
    let diceKeyID: String
    let name: String
    var title = "Unlock"
    var onUnlocked: (DiceKey) -> Void = { _ in }

    @Environment(UnlockedDiceKeys.self) private var unlocked
    @Environment(SavedDiceKeys.self) private var saved
    @State private var error: PresentableError?

    var body: some View {
        Button(title, systemImage: "faceid") {
            Task {
                do {
                    let diceKey = try await saved.load(id: diceKeyID, name: name)
                    unlocked.unlock(diceKey)
                    onUnlocked(diceKey)
                } catch  where !error.isAuthenticationCancellation {
                    self.error = PresentableError(title: "Couldn't Unlock", error: error)
                } catch {}
            }
        }
        .errorAlert($error)
    }
}
