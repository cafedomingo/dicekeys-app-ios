//
//  CatalogImport.swift
//  DiceKeyVault
//

import SwiftData
import SwiftUI

extension View {
    /// Asks before merging a catalog file into this device's catalog, then says what it added.
    /// Merging only adds; nothing in the catalog is removed or renamed.
    func importsCatalog(_ file: Binding<CatalogFile?>) -> some View {
        modifier(ImportsCatalog(file: file))
    }
}

private struct ImportsCatalog: ViewModifier {
    @Binding var file: CatalogFile?
    @Environment(\.modelContext) private var context
    @State private var summary: String?
    @State private var error: PresentableError?

    func body(content: Content) -> some View {
        content
            .confirmationDialog(
                "Import catalog?",
                isPresented: Binding(get: { file != nil }, set: { if !$0 { file = nil } }),
                titleVisibility: .visible, presenting: file
            ) { file in
                Button("Add what's new") { merge(file) }
            } message: { file in
                let diceKeyNames = file.diceKeys.map(\.name).formatted(.list(type: .and))
                let keyNames = file.keys.map(\.recipe.title).formatted(.list(type: .and))
                let keys = file.keys.isEmpty ? "" : ": \(Self.count(file.keys.count, "key")) (\(keyNames))"
                Text(
                    "\(diceKeyNames)\(keys). Only what this device doesn't have yet is added. Public keys are worked out from the dice, never taken from the file."
                )
            }
            .alert(
                "Imported", isPresented: Binding(get: { summary != nil }, set: { if !$0 { summary = nil } }),
                presenting: summary
            ) { _ in
                Button("OK", role: .cancel) {}
            } message: { summary in
                Text(summary)
            }
            .errorAlert($error)
    }

    private func merge(_ file: CatalogFile) {
        do {
            let added = try file.merge(into: context)
            let unreadable =
                added.unreadable == 0 ? "" : " \(Self.count(added.unreadable, "key")) couldn't be read."
            let addedText = "Added \(Self.count(added.diceKeys, "DiceKey")) and \(Self.count(added.keys, "key"))."
            summary = addedText + unreadable
        } catch {
            self.error = PresentableError(title: "Couldn't Import", error: error)
        }
    }

    private static func count(_ number: Int, _ noun: String) -> String {
        "\(number) \(noun)\(number == 1 ? "" : "s")"
    }
}
