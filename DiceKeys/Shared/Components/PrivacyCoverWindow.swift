//
//  PrivacyCoverWindow.swift
//  DiceKeys
//

import SwiftUI
import UIKit

/// Puts the privacy cover in a window of its own, above everything the app presents.
///
/// A view overlay cannot do this job: UIKit presents sheets in a layer above the root
/// view's overlays, so a root overlay leaves any sheet uncovered, and a cover applied
/// inside each sheet draws a second one over the first. A window at a raised level is
/// above sheets, alerts and the keyboard alike, and there is only ever one of it.
///
/// Shown from the scene notification rather than from SwiftUI's `scenePhase`, because
/// UIKit snapshots the scene as soon as `sceneDidEnterBackground` returns and will not
/// wait for a render pass. Observing with a `nil` queue delivers synchronously on the
/// posting thread, so the window is up before the notification returns.
@MainActor
final class PrivacyCoverWindowController {
    private var coverWindow: UIWindow?
    private var observers: [any NSObjectProtocol] = []

    /// The cover is removed on `willEnterForeground` rather than on becoming active: iOS
    /// hands `.active` back as much as a second later, and the user is looking at the app
    /// long before that.
    func startObserving() {
        let center = NotificationCenter.default
        observers.append(
            center.addObserver(forName: UIScene.didEnterBackgroundNotification, object: nil, queue: nil) { note in
                guard let scene = note.object as? UIWindowScene else { return }
                MainActor.assumeIsolated { self.show(over: scene) }
            }
        )
        observers.append(
            center.addObserver(forName: UIScene.willEnterForegroundNotification, object: nil, queue: nil) { _ in
                MainActor.assumeIsolated { self.hide() }
            }
        )
    }

    private func show(over scene: UIWindowScene) {
        let window = coverWindow ?? makeWindow(over: scene)
        coverWindow = window
        // No animation: the snapshot is taken on return and would catch a half-faded cover.
        window.alpha = 1
        window.isHidden = false
    }

    private func hide() {
        guard let window = coverWindow else { return }
        UIView.animate(withDuration: 0.25) {
            window.alpha = 0
        } completion: { _ in
            window.isHidden = true
        }
    }

    private func makeWindow(over scene: UIWindowScene) -> UIWindow {
        let window = UIWindow(windowScene: scene)
        // Above alerts, so nothing the app or the system presents can sit on top of it.
        window.windowLevel = .alert + 1
        // Never becomes key, and swallows nothing: the app is on its way out when it appears.
        window.isUserInteractionEnabled = false
        let host = UIHostingController(rootView: PrivacyCoverView())
        host.view.backgroundColor = .clear
        window.rootViewController = host
        return window
    }
}
