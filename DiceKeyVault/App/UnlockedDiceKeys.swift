//
//  UnlockedDiceKeys.swift
//  DiceKeyVault
//

import Foundation
import Observation

/// The DiceKeys held in memory, and nowhere else. The one in use, the last one opened or
/// unlocked, stays unlocked while the app is open, home included; any other locks `lockDelay`
/// after it stops being in use, and every one locks that long after the app goes to the
/// background.
@MainActor @Observable
final class UnlockedDiceKeys {
    static let lockDelay: TimeInterval = 59

    private(set) var diceKeys: [String: DiceKey] = [:]
    /// When each DiceKey that is counting down locks.
    private(set) var deadlines: [String: Date] = [:]
    @ObservationIgnored private var inUseID: String?
    @ObservationIgnored private var lockTask: Task<Void, Never>?

    func diceKey(id: String) -> DiceKey? { diceKeys[id] }

    func locksAt(id: String) -> Date? { deadlines[id] }

    func unlock(_ diceKey: DiceKey) {
        diceKeys[diceKey.id] = diceKey
        inUseID = diceKey.id
        updateDeadlines()
    }

    func lock(id: String) {
        diceKeys[id] = nil
        deadlines[id] = nil
        if inUseID == id { inUseID = nil }
        scheduleLock()
    }

    /// A DiceKey opened on screen, or one of its keys. Going back to home or the camera
    /// doesn't end its use; opening or unlocking another DiceKey does.
    func use(id: String) {
        inUseID = id
        updateDeadlines()
    }

    /// A suspended app can't run a timer, so every DiceKey starts counting down on the way
    /// out, and the deadlines are settled on the way back.
    func appWentToBackground(at date: Date = .now) {
        for id in diceKeys.keys { startCountdown(id: id, from: date) }
        scheduleLock()
    }

    func appReturned(at date: Date = .now) {
        lockExpired(at: date)
        updateDeadlines(from: date)
    }

    private func updateDeadlines(from date: Date = .now) {
        for id in diceKeys.keys {
            if id == inUseID { deadlines[id] = nil } else { startCountdown(id: id, from: date) }
        }
        scheduleLock()
    }

    /// Never pushes back a deadline already set.
    private func startCountdown(id: String, from date: Date) {
        let deadline = date.addingTimeInterval(Self.lockDelay)
        if let existing = deadlines[id], existing <= deadline { return }
        deadlines[id] = deadline
    }

    private func lockExpired(at date: Date) {
        for (id, deadline) in deadlines where deadline <= date {
            diceKeys[id] = nil
            deadlines[id] = nil
        }
    }

    private func scheduleLock() {
        lockTask?.cancel()
        guard let next = deadlines.values.min() else { return }
        lockTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(next.timeIntervalSinceNow))
            guard !Task.isCancelled, let self else { return }
            self.lockExpired(at: .now)
            self.scheduleLock()
        }
    }
}
