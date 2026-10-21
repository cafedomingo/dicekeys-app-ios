//
//  RecoveryRestore.swift
//  DiceKeyVault
//

import SwiftData
import SwiftUI

extension View {
    /// Asks before restoring a recovery sheet's DiceKey and its keys, and in the same alert
    /// whether to keep the DiceKey on this device, then hands it back to unlock.
    func restoresDiceKey(_ code: Binding<RecoveryCode?>, onRestored: @escaping (DiceKey) -> Void) -> some View {
        modifier(RestoresDiceKey(code: code, onRestored: onRestored))
    }
}

private struct RestoresDiceKey: ViewModifier {
    @Binding var code: RecoveryCode?
    let onRestored: (DiceKey) -> Void
    @Environment(\.modelContext) private var context
    @Environment(SavedDiceKeys.self) private var saved
    @State private var error: PresentableError?

    private var name: String { code?.catalog.diceKeys.first?.name ?? "" }

    func body(content: Content) -> some View {
        content
            .alert(
                "Restore \(name)?", isPresented: Binding(get: { code != nil }, set: { if !$0 { code = nil } }),
                presenting: code
            ) { code in
                Button("Restore and keep on this device") { restore(code, keeping: true) }
                Button("Restore") { restore(code, keeping: false) }
                Button("Cancel", role: .cancel) {}
            } message: { code in
                Text(
                    "Adds \(name) and its ^[\(code.catalog.keys.count) key](inflect: true) to this device, unlocked. Kept on this device, Face ID or the passcode unlocks it next time instead of this sheet."
                )
            }
            .errorAlert($error)
    }

    private func restore(_ code: RecoveryCode, keeping: Bool) {
        let diceKey: DiceKey
        do {
            diceKey = try code.restore(into: context)
        } catch {
            self.error = PresentableError(title: "Couldn't Restore", error: error)
            return
        }
        onRestored(diceKey)
        guard keeping else { return }
        do {
            try saved.save(diceKey)
        } catch {
            self.error = PresentableError(title: "Keychain Unavailable", error: error)
        }
    }
}
