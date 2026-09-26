//
//  RootView.swift
//  DiceKeys
//
//  Created by Stuart Schechter on 2020/11/24.
//

import SwiftUI

/// The root of the app: a `NavigationStack` driven by `AppRouter`, with the
/// home screen at its root.
struct RootView: View {
    @Environment(AppRouter.self) private var router
    @Environment(DiceKeyMemoryStore.self) private var diceKeyMemoryStore
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        @Bindable var router = router

        NavigationStack(path: $router.path) {
            HomeView()
                .navigationDestination(for: Route.self) { route in
                    destination(for: route)
                }
        }
        .privacyCover()
        .onChange(of: router.path) { oldPath, newPath in
            // Leaving the DiceKey screen (by any route) starts the expiration countdown.
            if oldPath.contains(.diceKey) && !newPath.contains(.diceKey) {
                diceKeyMemoryStore.clearForegroundDiceKey()
            }
        }
        .onChange(of: scenePhase) { _, phase in
            // A DiceKey on screen must not stay unlocked just because the app was suspended.
            switch phase {
            case .background: diceKeyMemoryStore.appDidEnterBackground()
            case .active: diceKeyMemoryStore.appDidBecomeActive()
            default: break
            }
        }
        .onChange(of: diceKeyMemoryStore.foregroundDiceKeyId) { _, keyId in
            // The foreground DiceKey expired or was erased while we were showing it.
            if keyId.isEmpty && router.path.contains(.diceKey) {
                router.popToRoot()
            }
        }
    }

    @ViewBuilder
    private func destination(for route: Route) -> some View {
        switch route {
        case .loadDiceKey:
            LoadDiceKeyScreen(onDiceKeyLoaded: { diceKey, _ in
                diceKeyMemoryStore.setDiceKey(diceKey: diceKey)
                router.presentDiceKey()
            })
        case .assemblyInstructions:
            AssemblyInstructionsScreen(onSuccess: { diceKey in
                diceKeyMemoryStore.setDiceKey(diceKey: diceKey)
                router.presentDiceKey()
            })
        case .diceKey:
            DiceKeyScreen()
        case .derive(let source):
            DerivedValueScreen(source: source)
        }
    }
}

#Preview {
    RootView()
        .appEnvironment(AppModel.preview())
}
