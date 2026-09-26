//
//  DiceKeysApp.swift
//  DiceKeys
//
//  Created by Stuart Schechter on 2020/11/23.
//

import SwiftUI

@main
struct DiceKeysApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            RootView()
                .appEnvironment(model)
        }
    }
}
