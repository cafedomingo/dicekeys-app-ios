//
//  LoadScreen.swift
//  DiceKeyVault
//

import SwiftUI

/// The camera, with typing the dice in as the fallback. The camera also reads list cards'
/// and recovery sheets' codes.
struct LoadScreen: View {
    let onLoaded: (DiceKey) -> Void
    let onCodeRead: (String) -> Void
    /// Leaves the scanner. A phone has Back for this; a wider screen keeps the sidebar beside
    /// it, which before the first DiceKey offers nothing else to go to.
    let onClose: () -> Void

    @State private var isTyping = false
    /// Kept across switching to the camera and back, and dropped once loaded or when the app
    /// has been in the background as long as an unlocked DiceKey may be, since half a DiceKey
    /// is still most of a secret.
    @State private var typed = TypedDiceKey()
    @State private var backgroundedAt: Date?
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.horizontalSizeClass) private var sizeClass

    var body: some View {
        Group {
            if isTyping {
                TypingView(typed: typed, onDone: load)
            } else {
                ScanDiceKeyView(onDiceKeyRead: load, onCodeRead: onCodeRead)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.bg)
        .navigationTitle(isTyping ? "Type it in" : "Scan DiceKey")
        .toolbarTitleDisplayMode(isTyping ? .inline : .automatic)
        .toolbar {
            if sizeClass != .compact {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close", systemImage: "xmark", action: onClose)
                }
            }
            ToolbarItem(placement: .primaryAction) {
                Button(
                    isTyping ? "Scan" : "Type it in",
                    systemImage: isTyping ? "camera.viewfinder" : "keyboard"
                ) { isTyping.toggle() }
            }
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .background:
                backgroundedAt = backgroundedAt ?? .now
            case .active:
                if let backgroundedAt, Date.now.timeIntervalSince(backgroundedAt) >= UnlockedDiceKeys.lockDelay {
                    typed = TypedDiceKey()
                }
                backgroundedAt = nil
            default:
                break
            }
        }
    }

    private func load(_ diceKey: DiceKey) {
        typed = TypedDiceKey()
        onLoaded(diceKey)
    }
}
