//
//  PrivacyCoverVisibilityTests.swift
//  DiceKeysTests
//
//  The cover hides the screen from the app-switcher snapshot, and iOS takes that snapshot
//  on the way to the background. It also covers while the scene is merely inactive, which
//  is what a Face ID sheet makes it, and that is the one case worth relaxing: once the user
//  has authenticated to us there is no snapshot coming, only iOS dismissing its own sheet.
//

import SwiftUI
import Testing
@testable import DiceKeys

struct PrivacyCoverVisibilityTests {
    @Test("an active scene is never covered")
    func activeIsUncovered() {
        #expect(!privacyCoverIsVisible(scenePhase: .active, authenticationJustSucceeded: false))
        #expect(!privacyCoverIsVisible(scenePhase: .active, authenticationJustSucceeded: true))
    }

    @Test("an inactive scene is covered, because the sheet over it may not be ours")
    func inactiveIsCovered() {
        #expect(privacyCoverIsVisible(scenePhase: .inactive, authenticationJustSucceeded: false))
    }

    @Test("an inactive scene uncovers early once the user has authenticated to us")
    func inactiveUncoversAfterAuthenticating() {
        #expect(!privacyCoverIsVisible(scenePhase: .inactive, authenticationJustSucceeded: true))
    }

    @Test("a backgrounded scene is covered even straight after authenticating")
    func backgroundIsAlwaysCovered() {
        #expect(privacyCoverIsVisible(scenePhase: .background, authenticationJustSucceeded: false))
        // The snapshot iOS takes for the app switcher would otherwise catch a DiceKey whose
        // dice the user had revealed.
        #expect(privacyCoverIsVisible(scenePhase: .background, authenticationJustSucceeded: true))
    }
}
