//
//  Concealment.swift
//  DiceKeys
//

import SwiftUI
import UIKit

extension View {
    /// Hides a secret again whenever it could be seen by more than the user: the app leaves
    /// the foreground, the screen is recorded or mirrored, or a screenshot is taken. A
    /// screenshot can't be prevented, only kept from catching the next secret.
    func concealsWhenExposed(_ isShown: Binding<Bool>) -> some View {
        modifier(ConcealsWhenExposed(isShown: isShown))
    }
}

private struct ConcealsWhenExposed: ViewModifier {
    private static let screenshots = NotificationCenter.default.publisher(
        for: UIApplication.userDidTakeScreenshotNotification)

    @Binding var isShown: Bool
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.isSceneCaptured) private var isSceneCaptured

    func body(content: Content) -> some View {
        content
            .onChange(of: scenePhase) { _, phase in
                if phase != .active { isShown = false }
            }
            .onChange(of: isSceneCaptured, initial: true) { _, isCaptured in
                if isCaptured { isShown = false }
            }
            .onReceive(Self.screenshots) { _ in isShown = false }
    }
}
