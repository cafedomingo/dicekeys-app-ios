//
//  DiceKeyMemoryStoreLifecycleTests.swift
//  DiceKeysTests
//
//  Backgrounding the app must not keep a DiceKey unlocked indefinitely: a key left on
//  screen starts the same countdown as leaving its screen, measured from when the app
//  went to the background.
//

import Foundation
import Testing
@testable import DiceKeys

@MainActor
struct DiceKeyMemoryStoreLifecycleTests {
    private func makeStore() -> DiceKeyMemoryStore {
        let defaults = UserDefaults(suiteName: "DiceKeyMemoryStoreLifecycleTests.\(UUID().uuidString)")!
        let keychain = DiceKeyKeychain()
        return DiceKeyMemoryStore(
            knownDiceKeysStore: KnownDiceKeysStore(defaults: defaults, keychain: keychain),
            keychain: keychain
        )
    }

    @Test("a DiceKey left on screen expires if the app stays in the background past the countdown")
    func expiresAfterLongBackground() {
        let store = makeStore()
        store.setDiceKey(diceKey: DiceKey.Example)
        let backgrounded = Date()
        store.appDidEnterBackground(at: backgrounded)
        store.appDidBecomeActive(at: backgrounded.addingTimeInterval(10 * 60))
        #expect(store.diceKeyLoaded == nil)
        #expect(store.memoryStoreExpirationState == .empty)
    }

    @Test("a short trip to the background keeps the DiceKey on screen, with the countdown deferred again")
    func survivesShortBackground() {
        let store = makeStore()
        store.setDiceKey(diceKey: DiceKey.Example)
        let backgrounded = Date()
        store.appDidEnterBackground(at: backgrounded)
        #expect(store.isCountdownTimerRunning)
        store.appDidBecomeActive(at: backgrounded.addingTimeInterval(5))
        #expect(store.diceKeyLoaded != nil)
        #expect(store.memoryStoreExpirationState == .countdownDeferred)
    }

    @Test("after returning from the background, leaving the DiceKey starts a full countdown")
    func leavingAfterReturnRestartsTheCountdown() {
        let store = makeStore()
        store.setDiceKey(diceKey: DiceKey.Example)
        let backgrounded = Date().addingTimeInterval(-50)
        store.appDidEnterBackground(at: backgrounded)
        store.appDidBecomeActive(at: backgrounded.addingTimeInterval(50))
        store.clearForegroundDiceKey()
        // Not the 9 seconds left of the countdown that ran while in the background.
        #expect(store.timeRemainingInFractionalSeconds > 50)
    }

    @Test("keys the user chose to keep until quitting survive the background")
    func keepUntilQuitIsRespected() {
        let store = makeStore()
        store.setDiceKey(diceKey: DiceKey.Example)
        store.setKeysNeverExpire()
        let backgrounded = Date()
        store.appDidEnterBackground(at: backgrounded)
        store.appDidBecomeActive(at: backgrounded.addingTimeInterval(24 * 60 * 60))
        #expect(store.diceKeyLoaded != nil)
    }

    @Test("an extended countdown keeps running on wall-clock time while in the background")
    func extendedCountdownKeepsRunning() {
        let store = makeStore()
        store.setDiceKey(diceKey: DiceKey.Example)
        store.clearForegroundDiceKey()
        store.extendDeadlineBy(seconds: 60 * 60)
        let backgrounded = Date()
        store.appDidEnterBackground(at: backgrounded)
        store.appDidBecomeActive(at: backgrounded.addingTimeInterval(30 * 60))
        #expect(store.allDiceKeys.count == 1)
        #expect(store.isCountdownTimerRunning)
        store.appDidEnterBackground(at: backgrounded.addingTimeInterval(30 * 60))
        store.appDidBecomeActive(at: backgrounded.addingTimeInterval(2 * 60 * 60))
        #expect(store.allDiceKeys.isEmpty)
    }
}
