//
//  DiceKeysApp.swift
//  DiceKeys
//

import SwiftData
import SwiftUI

@main
struct DiceKeysApp: App {
    @State private var unlocked = UnlockedDiceKeys()
    @State private var saved = SavedDiceKeys()
    private let catalog: ModelContainer
    /// Why the synced store didn't open, when the app fell back to this device's copy so
    /// Settings stays reachable to turn sync off.
    private let syncFailure: String?
    // Not `@State`: it is never read from `body`, and reading a `@State` value from an
    // initializer is outside what SwiftUI supports.
    private let privacyCover = PrivacyCoverWindowController()

    init() {
        do {
            catalog = try Catalog.container()
            syncFailure = nil
        } catch let error where Catalog.syncsThisLaunch {
            do {
                catalog = try Catalog.container(syncing: false)
            } catch {
                fatalError("The catalog store can't be opened: \(error)")
            }
            syncFailure = error.localizedDescription
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
                .environment(\.catalogSyncFailure, syncFailure)
        }
    }
}

extension EnvironmentValues {
    @Entry var catalogSyncFailure: String?
}
