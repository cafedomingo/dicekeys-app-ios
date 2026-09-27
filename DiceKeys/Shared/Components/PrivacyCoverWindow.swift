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
/// above sheets, alerts and the keyboard alike, and there is only ever one per scene.
///
/// Shown from the scene notification rather than from SwiftUI's `scenePhase`, because
/// UIKit snapshots the scene as soon as `sceneDidEnterBackground` returns and will not
/// wait for a render pass. Observing with a `nil` queue delivers synchronously on the
/// posting thread, so the window is up before the notification returns.
@MainActor
final class PrivacyCoverWindowController {
    /// One cover per scene, keyed by scene identity: a window belongs to the scene it was
    /// made for, so it cannot stand in for another one, and iPadOS can show several scenes
    /// of this app at once. Dropped when the scene disconnects, which iOS can do to a
    /// backgrounded app while the process lives on.
    private var coverWindows: [ObjectIdentifier: UIWindow] = [:]
    /// Held so they can be unregistered. The handlers capture `self` weakly, so a discarded
    /// controller is not kept alive by the notification centre while it waits for `deinit`.
    nonisolated(unsafe) private var observers: [any NSObjectProtocol] = []

    /// The cover is removed on `willEnterForeground` rather than on becoming active: iOS
    /// hands `.active` back as much as a second later, and the user is looking at the app
    /// long before that.
    func startObserving() {
        observe(UIScene.didEnterBackgroundNotification) { [weak self] in self?.show(over: $0) }
        observe(UIScene.willEnterForegroundNotification) { [weak self] in self?.hide(over: $0) }
        observe(UIScene.didDisconnectNotification) { [weak self] in self?.discardWindow(for: $0) }
    }

    deinit {
        observers.forEach(NotificationCenter.default.removeObserver)
    }

    private func observe(_ name: Notification.Name, _ handler: @escaping @MainActor (UIWindowScene) -> Void) {
        observers.append(
            NotificationCenter.default.addObserver(forName: name, object: nil, queue: nil) { note in
                guard let scene = note.object as? UIWindowScene else { return }
                // Safe because `queue: nil` delivers on the posting thread, and UIKit posts
                // scene lifecycle notifications on the main thread.
                MainActor.assumeIsolated { handler(scene) }
            }
        )
    }

    private func show(over scene: UIWindowScene) {
        let key = ObjectIdentifier(scene)
        let window = coverWindows[key] ?? makeWindow(over: scene)
        coverWindows[key] = window
        // No animation, and any fade still running is cut short rather than left to play
        // out: the snapshot is taken as soon as this returns and would otherwise catch a
        // half-faded cover.
        window.layer.removeAllAnimations()
        window.alpha = 1
        window.isHidden = false
    }

    private func hide(over scene: UIWindowScene) {
        guard let window = coverWindows[ObjectIdentifier(scene)] else { return }
        // iOS can deliver foregrounding twice in quick succession; a second fade layered on
        // the first would leave the window at some middling alpha.
        window.layer.removeAllAnimations()
        UIView.animate(withDuration: 0.25) {
            window.alpha = 0
        } completion: { _ in
            // Unless the scene went back to the background mid-fade, in which case `show`
            // has already restored the alpha and the cover has to stay up.
            if window.alpha == 0 { window.isHidden = true }
        }
    }

    /// The cover standing over `scene`, if one has been raised for it.
    func coverWindow(for scene: UIWindowScene) -> UIWindow? {
        coverWindows[ObjectIdentifier(scene)]
    }

    private func discardWindow(for scene: UIWindowScene) {
        coverWindows.removeValue(forKey: ObjectIdentifier(scene))
    }

    private func makeWindow(over scene: UIWindowScene) -> UIWindow {
        let window = UIWindow(windowScene: scene)
        // Above every context the app can present into: sheets, alerts and the keyboard.
        // Not above system chrome such as the screenshot flash, which does not matter.
        window.windowLevel = .alert + 1
        // Never becomes key, and swallows nothing: the app is on its way out when it appears.
        window.isUserInteractionEnabled = false
        let host = UIHostingController(rootView: PrivacyCoverView())
        host.view.backgroundColor = .clear
        window.rootViewController = host
        return window
    }
}
