//
//  AppRouter.swift
//  DiceKeys
//
//  The single source of truth for navigation. `RootView` binds a
//  `NavigationStack` to `path`; every screen that wants to navigate pushes a
//  typed `Route` rather than flipping booleans.
//

import Observation

/// Every screen reachable by pushing onto the root `NavigationStack`.
enum Route: Hashable {
    /// Scan or type a DiceKey.
    case loadDiceKey
    /// Step-by-step assembly instructions for a new DiceKey kit.
    case assemblyInstructions
    /// The DiceKey currently in the foreground of `DiceKeyMemoryStore`.
    case diceKey
    /// Derive a password, key, or secret from the foreground DiceKey.
    case derive(RecipeSource)
}

@MainActor @Observable
final class AppRouter {
    var path: [Route] = []

    /// Set by "Save this DiceKey" so that `DiceKeyScreen` opens the storage
    /// options sheet as soon as it appears. Cleared by the screen that consumes it.
    var showStorageOptionsOnPresent = false

    func push(_ route: Route) {
        path.append(route)
    }

    func popToRoot() {
        path.removeAll()
    }

    /// Replace the whole stack with the DiceKey screen for the foreground DiceKey.
    func presentDiceKey(showStorageOptions: Bool = false) {
        showStorageOptionsOnPresent = showStorageOptions
        path = [.diceKey]
    }
}
