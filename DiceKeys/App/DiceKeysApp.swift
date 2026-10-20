//
//  DiceKeysApp.swift
//  DiceKeys
//

import SwiftData
import SwiftUI

enum AppInfo {
    static let name = "DiceKey Vault"
}

@main
struct DiceKeysApp: App {
    @State private var unlocked = UnlockedDiceKeys()
    @State private var saved = SavedDiceKeys()
    private let catalog: ModelContainer
    // Not `@State`: it is never read from `body`, and reading a `@State` value from an
    // initializer is outside what SwiftUI supports.
    private let privacyCover = PrivacyCoverWindowController()

    init() {
        do {
            catalog = try Catalog.container()
        } catch {
            fatalError("The catalog store can't be opened: \(error)")
        }
        privacyCover.startObserving()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(unlocked)
                .environment(saved)
                .modelContainer(catalog)
        }
    }
}
