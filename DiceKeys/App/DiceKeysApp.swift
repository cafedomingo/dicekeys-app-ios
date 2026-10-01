//
//  DiceKeysApp.swift
//  DiceKeys
//

import SwiftUI

@main
struct DiceKeysApp: App {
    @State private var model = AppModel()
    // Not `@State`: it is never read from `body`, and reading a `@State` value from an
    // initializer is outside what SwiftUI supports.
    private let privacyCover = PrivacyCoverWindowController()

    init() {
        privacyCover.startObserving()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .appEnvironment(model)
        }
    }
}
