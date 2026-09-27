//
//  PrivacyCoverWindowTests.swift
//  DiceKeysTests
//
//  Which notifications the cover listens to is the whole policy, so these pin it. The
//  tempting mistakes are covering when the scene merely deactivates, which hides the app
//  behind the Face ID prompt and Control Center, and uncovering on activation, which iOS
//  can withhold for about a second after the user is already looking at the app.
//

import Testing
import UIKit
@testable import DiceKeys

@MainActor
@Suite(.serialized)
struct PrivacyCoverWindowTests {
    private func firstScene() throws -> UIWindowScene {
        try #require(UIApplication.shared.connectedScenes.first as? UIWindowScene)
    }

    private func observingController() -> PrivacyCoverWindowController {
        let controller = PrivacyCoverWindowController()
        controller.startObserving()
        return controller
    }

    @Test("backgrounding raises a cover over the scene")
    func backgroundingRaisesTheCover() throws {
        let scene = try firstScene()
        let controller = observingController()
        #expect(controller.coverWindow(for: scene) == nil)

        NotificationCenter.default.post(name: UIScene.didEnterBackgroundNotification, object: scene)

        let window = try #require(controller.coverWindow(for: scene))
        #expect(!window.isHidden)
        #expect(window.alpha == 1)
    }

    @Test("foregrounding fades the cover out")
    func foregroundingFadesTheCoverOut() throws {
        let scene = try firstScene()
        let controller = observingController()
        NotificationCenter.default.post(name: UIScene.didEnterBackgroundNotification, object: scene)

        NotificationCenter.default.post(name: UIScene.willEnterForegroundNotification, object: scene)

        // `UIView.animate` sets the value straight away and animates the presentation, so
        // the fade having started is visible without waiting for it to finish.
        let window = try #require(controller.coverWindow(for: scene))
        #expect(window.alpha == 0)
    }

    @Test("a scene merely deactivating is not covered")
    func deactivatingDoesNotCover() throws {
        let scene = try firstScene()
        let controller = observingController()

        // The Face ID prompt, Control Center and the app switcher gesture all land here.
        // UIKit takes no snapshot for them, and iOS hands activation back long after they
        // have gone, so covering here hides the app with nothing left to hide it from.
        NotificationCenter.default.post(name: UIScene.willDeactivateNotification, object: scene)

        #expect(controller.coverWindow(for: scene) == nil)
    }

    @Test("the cover of a disconnected scene is discarded rather than reused")
    func disconnectingDiscardsTheCover() throws {
        let scene = try firstScene()
        let controller = observingController()
        NotificationCenter.default.post(name: UIScene.didEnterBackgroundNotification, object: scene)
        #expect(controller.coverWindow(for: scene) != nil)

        NotificationCenter.default.post(name: UIScene.didDisconnectNotification, object: scene)

        #expect(controller.coverWindow(for: scene) == nil)
    }
}
