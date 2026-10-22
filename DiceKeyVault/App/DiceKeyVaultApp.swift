//
//  DiceKeyVaultApp.swift
//  DiceKeyVault
//

import SwiftData
import SwiftUI
import UIKit

@main
struct DiceKeyVaultApp: App {
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
        Self.elevateScenes()
    }

    /// Every scene is elevated, as a sheet is, so that in dark the system draws list rows a step
    /// lighter than `bg` and keeps its own tap and selection highlights. `queue: nil` delivers
    /// on the posting thread, and UIKit connects scenes on the main thread.
    private static func elevateScenes() {
        _ = NotificationCenter.default.addObserver(
            forName: UIScene.willConnectNotification, object: nil, queue: nil
        ) { note in
            guard let scene = note.object as? UIWindowScene else { return }
            MainActor.assumeIsolated { scene.traitOverrides.userInterfaceLevel = .elevated }
        }
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
