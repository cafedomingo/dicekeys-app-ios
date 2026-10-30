//
//  LoadScreen.swift
//  DiceKeyVault
//

import SwiftUI

/// The camera, with typing the dice in as the fallback. The camera also reads list cards'
/// and recovery sheets' codes. A compact window centers its content; a wider one sits it
/// under the title, so a tall column doesn't leave a gap between them.
struct LoadScreen: View {
    /// The window's size class, not this column's, which can report its own.
    let isCompact: Bool
    /// This and `typed` are held by the caller, since a resize can move this screen and start a
    /// new one.
    @Binding var isTyping: Bool
    let typed: TypedDiceKey
    let onLoaded: (DiceKey) -> Void
    let onCodeRead: (String) -> Void

    var body: some View {
        Group {
            if isTyping {
                TypingView(typed: typed, onDone: onLoaded)
            } else {
                ScanDiceKeyView(onDiceKeyRead: onLoaded, onCodeRead: onCodeRead)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: isCompact ? .center : .top)
        .background(Color.bg)
        .navigationTitle(isTyping ? "Type it in" : "Scan DiceKey")
        .toolbarTitleDisplayMode(isTyping ? .inline : .automatic)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button(
                    isTyping ? "Scan" : "Type it in",
                    systemImage: isTyping ? "camera.viewfinder" : "keyboard"
                ) { isTyping.toggle() }
            }
        }
    }
}
