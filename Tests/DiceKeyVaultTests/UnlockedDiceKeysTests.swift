//
//  UnlockedDiceKeysTests.swift
//  DiceKeyVaultTests
//
//  The DiceKey in use, the last one opened or unlocked, stays unlocked wherever the app is;
//  any other counts down `lockDelay`. A suspended app can't run that countdown, so it is
//  settled when the app comes back.
//

import Foundation
import Testing

@testable import DiceKeyVault

@MainActor
struct UnlockedDiceKeysTests {
    private let first = DiceKey.example
    /// The example's faces in reverse order: a different DiceKey.
    private let second = DiceKey(DiceKey.example.faces.reversed())

    @Test("an unlocked DiceKey is in use, so it doesn't count down")
    func unlockingPutsInUse() {
        let unlocked = UnlockedDiceKeys()
        unlocked.unlock(first)
        #expect(unlocked.diceKey(id: first.id) != nil)
        #expect(unlocked.locksAt(id: first.id) == nil)
    }

    @Test("unlocking another DiceKey starts the countdown of the one left")
    func unlockingAnotherStartsCountdown() {
        let unlocked = UnlockedDiceKeys()
        unlocked.unlock(first)
        unlocked.unlock(second)
        #expect(unlocked.locksAt(id: first.id) != nil)
        #expect(unlocked.locksAt(id: second.id) == nil)
    }

    @Test("using a DiceKey stops its countdown and starts the other's")
    func usingSwitches() {
        let unlocked = UnlockedDiceKeys()
        unlocked.unlock(first)
        unlocked.unlock(second)
        unlocked.use(id: first.id)
        #expect(unlocked.locksAt(id: first.id) == nil)
        #expect(unlocked.locksAt(id: second.id) != nil)
    }

    @Test("locking the DiceKey in use doesn't keep it in use once unlocked again elsewhere")
    func lockingClearsUse() {
        let unlocked = UnlockedDiceKeys()
        unlocked.unlock(first)
        unlocked.unlock(second)
        unlocked.lock(id: second.id)
        unlocked.use(id: first.id)
        #expect(unlocked.locksAt(id: first.id) == nil)
        #expect(unlocked.diceKey(id: second.id) == nil)
    }

    @Test("coming back after the deadline locks everything")
    func lateReturnLocks() {
        let unlocked = UnlockedDiceKeys()
        unlocked.unlock(first)
        let left = Date.now
        unlocked.appWentToBackground(at: left)
        unlocked.appReturned(at: left.addingTimeInterval(UnlockedDiceKeys.lockDelay + 1))
        #expect(unlocked.diceKeys.isEmpty)
        #expect(unlocked.deadlines.isEmpty)
    }

    @Test("coming back in time to the DiceKey in use stops its countdown")
    func earlyReturnKeeps() {
        let unlocked = UnlockedDiceKeys()
        unlocked.unlock(first)
        let left = Date.now
        unlocked.appWentToBackground(at: left)
        unlocked.appReturned(at: left.addingTimeInterval(1))
        #expect(unlocked.diceKey(id: first.id) != nil)
        #expect(unlocked.locksAt(id: first.id) == nil)
    }

    @Test("a later countdown never pushes back an earlier deadline")
    func deadlineNeverExtends() {
        let unlocked = UnlockedDiceKeys()
        unlocked.unlock(first)
        unlocked.unlock(second)
        let deadline = unlocked.locksAt(id: first.id)
        unlocked.appWentToBackground(at: .now.addingTimeInterval(30))
        #expect(unlocked.locksAt(id: first.id) == deadline)
    }
}
