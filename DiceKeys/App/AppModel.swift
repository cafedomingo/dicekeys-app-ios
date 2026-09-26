//
//  AppModel.swift
//  DiceKeys
//
//  The composition root. It owns one store per concern and hands them to the
//  view tree through the SwiftUI environment (see `appEnvironment(_:)`).
//  Nothing else in the app holds a global; previews and tests build their own.
//

import SwiftUI

@MainActor @Observable
final class AppModel {
    let router: AppRouter
    let keychain: DiceKeyKeychain
    let knownDiceKeysStore: KnownDiceKeysStore
    let diceKeyMemoryStore: DiceKeyMemoryStore
    let recipeStore: DerivationRecipeStore

    init(defaults: UserDefaults = .standard, keychain: DiceKeyKeychain = DiceKeyKeychain()) {
        self.router = AppRouter()
        self.keychain = keychain
        let knownDiceKeysStore = KnownDiceKeysStore(defaults: defaults, keychain: keychain)
        self.knownDiceKeysStore = knownDiceKeysStore
        self.diceKeyMemoryStore = DiceKeyMemoryStore(knownDiceKeysStore: knownDiceKeysStore, keychain: keychain)
        self.recipeStore = DerivationRecipeStore(defaults: defaults)
    }

    /// A model for previews, with a DiceKey already unlocked in memory.
    static func preview(diceKey: DiceKey? = DiceKey.Example) -> AppModel {
        let model = AppModel(defaults: UserDefaults(suiteName: "preview") ?? .standard)
        if let diceKey {
            model.diceKeyMemoryStore.setDiceKey(diceKey: diceKey)
        }
        return model
    }
}

extension View {
    /// Injects every store owned by `model` so views can read them with
    /// `@Environment(SomeStore.self)`.
    func appEnvironment(_ model: AppModel) -> some View {
        self
            .environment(model)
            .environment(model.router)
            .environment(model.diceKeyMemoryStore)
            .environment(model.knownDiceKeysStore)
            .environment(model.recipeStore)
    }
}
