//
//  PrivacyCoverVisibilityTests.swift
//  DiceKeysTests
//
//  The cover exists for one moment: the snapshot UIKit takes for the app switcher as the
//  app backgrounds. These pin the rule to that moment, because the tempting mistake is to
//  cover whenever the scene is not active, which also fires for the Face ID prompt, Control
//  Center and Notification Center and leaves the screen hidden long after they have gone.
//

import SwiftUI
import Testing
@testable import DiceKeys

struct PrivacyCoverVisibilityTests {
    @Test("a backgrounded scene is covered, because that is when the snapshot is taken")
    func backgroundIsCovered() {
        #expect(privacyCoverIsVisible(scenePhase: .background))
    }

    @Test("an active scene is never covered")
    func activeIsUncovered() {
        #expect(!privacyCoverIsVisible(scenePhase: .active))
    }

    @Test("an inactive scene is not covered, so Face ID and Control Center do not hide the app")
    func inactiveIsUncovered() {
        // Resigning active is not a snapshot. Covering here is Apple's named anti-pattern
        // (QA1838): the app switcher gesture, Control Center, Notification Center and the
        // Face ID sheet all land in this phase, and `.active` comes back as much as a second
        // after the last of them closes.
        #expect(!privacyCoverIsVisible(scenePhase: .inactive))
    }
}
