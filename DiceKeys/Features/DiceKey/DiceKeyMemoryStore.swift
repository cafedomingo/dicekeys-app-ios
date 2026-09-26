//
//  DiceKeyMemoryStore.swift
//  DiceKeys
//
//  Created by Stuart Schechter on 2021/02/08.
//

import Foundation
import Observation

enum MemoryStoreExpirationState: Equatable {
    case empty
    case keysNeverExpire
    case countdownDeferred
    case countdownInProgress(whenExpiring: Date)
}

/// How long keys stay in memory after the user leaves a DiceKey (or backgrounds the app on
/// one); the expiration menu extends it. 59 rather than 60 so the countdown opens on 0:59.
private let defaultExpirationPeriodInSeconds: TimeInterval = 59

/// Holds the DiceKeys that are currently unlocked in memory, and expires them
/// after a countdown once the user has left the DiceKey screen or put the app in the
/// background.
@MainActor @Observable
final class DiceKeyMemoryStore {
    @ObservationIgnored private let knownDiceKeysStore: KnownDiceKeysStore
    @ObservationIgnored private let keychain: DiceKeyKeychain

    /// Updated once a second while a countdown is running so that views showing
    /// the time remaining refresh.
    private(set) var currentTime = Date()

    private(set) var memoryStoreExpirationState: MemoryStoreExpirationState = .empty {
        didSet { expirationStateChanged(from: oldValue) }
    }

    /// The id of the DiceKey the user is currently working with, or "" if none.
    private(set) var foregroundDiceKeyId: String = ""

    private var keyCache: [String: DiceKey] = [:]
    /// One `UnlockedDiceKeyState` per unlocked key, so views observing it share state.
    @ObservationIgnored private var unlockedStates: [String: UnlockedDiceKeyState] = [:]
    private var lastWhenExpiring: Date?
    @ObservationIgnored private var countdownTask: Task<Void, Never>?
    /// Set when backgrounding started the countdown for a DiceKey that was on screen, so
    /// returning in time can defer it again.
    @ObservationIgnored private var countdownStartedByBackground = false

    init(knownDiceKeysStore: KnownDiceKeysStore, keychain: DiceKeyKeychain) {
        self.knownDiceKeysStore = knownDiceKeysStore
        self.keychain = keychain
    }

    // MARK: Countdown timer

    private func expirationStateChanged(from oldValue: MemoryStoreExpirationState) {
        if case let .countdownInProgress(whenExpiring) = oldValue {
            lastWhenExpiring = whenExpiring
        }
        countdownTask?.cancel()
        countdownTask = nil
        if case .countdownInProgress = memoryStoreExpirationState {
            currentTime = Date()
            countdownTask = Task { [weak self] in
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(1))
                    guard !Task.isCancelled, let self else { return }
                    self.tick()
                }
            }
        }
    }

    private func tick() {
        currentTime = Date()
        if case let .countdownInProgress(whenExpiring) = memoryStoreExpirationState,
           currentTime > whenExpiring, !keyCache.isEmpty {
            expireAllKeys()
        }
    }

    // MARK: Expiring keys

    func expireKey(_ keyId: String) {
        keyCache.removeValue(forKey: keyId)
        unlockedStates.removeValue(forKey: keyId)
        if foregroundDiceKeyId == keyId {
            foregroundDiceKeyId = ""
        }
        if keyCache.isEmpty {
            memoryStoreExpirationState = .empty
        }
    }

    func expireKey(_ diceKey: DiceKey) {
        expireKey(diceKey.id)
    }

    func expireAllKeys() {
        keyCache = [:]
        unlockedStates = [:]
        foregroundDiceKeyId = ""
        memoryStoreExpirationState = .empty
    }

    func extendDeadlineBy(seconds: TimeInterval) {
        if case let .countdownInProgress(whenExpiring) = memoryStoreExpirationState {
            memoryStoreExpirationState = .countdownInProgress(whenExpiring: whenExpiring + seconds)
        } else {
            memoryStoreExpirationState = .countdownInProgress(whenExpiring: Date(timeIntervalSinceNow: seconds))
        }
    }

    func setKeysNeverExpire() {
        memoryStoreExpirationState = .keysNeverExpire
    }

    func startExpirationCountdown(_ whenExpiring: Date = Date().addingTimeInterval(defaultExpirationPeriodInSeconds)) {
        if let lastWhenExpiring, lastWhenExpiring > whenExpiring {
            // Don't set whenExpiring to something earlier than it is already set to.
            memoryStoreExpirationState = .countdownInProgress(whenExpiring: lastWhenExpiring)
        } else {
            memoryStoreExpirationState = .countdownInProgress(whenExpiring: whenExpiring)
        }
    }

    // MARK: Queries

    var allDiceKeys: [DiceKey] {
        keyCache.values.sorted { $0.centerFace.humanReadableForm < $1.centerFace.humanReadableForm }
    }

    func contains(_ keyId: String) -> Bool {
        keyCache[keyId] != nil
    }

    var isEmpty: Bool {
        if case .empty = memoryStoreExpirationState { return true } else { return false }
    }

    var isCountdownTimerRunning: Bool {
        if case .countdownInProgress = memoryStoreExpirationState { return true } else { return false }
    }

    var expirationTime: Date {
        if case let .countdownInProgress(whenExpiring) = memoryStoreExpirationState {
            return whenExpiring
        }
        return .distantFuture
    }

    var timeRemainingInFractionalSeconds: TimeInterval {
        expirationTime.timeIntervalSince(currentTime)
    }

    var secondsRemaining: Int {
        Int(timeRemainingInFractionalSeconds) % 60
    }

    var minutesRemaining: Int {
        Int(timeRemainingInFractionalSeconds) / 60
    }

    var formattedTimeRemaining: String {
        "\(minutesRemaining):\(String(format: "%02d", secondsRemaining))"
    }

    /// The DiceKey the user is currently working with, if it is still in memory.
    var diceKeyLoaded: DiceKey? {
        keyCache[foregroundDiceKeyId]
    }

    /// The observable state wrapper for the foreground DiceKey.
    var diceKeyState: UnlockedDiceKeyState? {
        diceKeyLoaded.map { unlockedState(for: $0) }
    }

    func unlockedState(for diceKey: DiceKey) -> UnlockedDiceKeyState {
        let keyId = diceKey.id
        if let existing = unlockedStates[keyId] {
            return existing
        }
        let state = UnlockedDiceKeyState(diceKey: diceKey, knownDiceKeysStore: knownDiceKeysStore, keychain: keychain)
        unlockedStates[keyId] = state
        return state
    }

    /// Whether the DiceKey's dice are saved (encrypted) in the keychain.
    func isStoredInKeychain(_ diceKey: DiceKey) -> Bool {
        keychain.hasDiceKey(forKeyId: diceKey.id)
    }

    /// Authenticates the user and loads a saved DiceKey into the foreground.
    func unlock(_ metadata: StoredEncryptedDiceKeyMetadata) async throws -> DiceKey {
        let diceKey = try await keychain.getDiceKey(fromKeyId: metadata.keyId, centerFace: metadata.centerFace)
        setDiceKey(diceKey: diceKey)
        return diceKey
    }

    // MARK: Loading keys

    func setDiceKey(diceKey: DiceKey) {
        let centerUprightDiceKey = diceKey.toCenterUprightRotation()
        let keyId = centerUprightDiceKey.id
        keyCache[keyId] = centerUprightDiceKey
        foregroundDiceKeyId = keyId
        // Defer expiration while we use this DiceKey
        memoryStoreExpirationState = .countdownDeferred
    }

    // MARK: App lifecycle

    /// The app went to the background at `date`. A DiceKey left on screen starts the same
    /// countdown as leaving its screen, so a suspended app cannot hold a key unlocked
    /// indefinitely. A running countdown carries on, and keys the user chose to keep until
    /// quitting are left alone.
    func appDidEnterBackground(at date: Date = Date()) {
        if case .countdownDeferred = memoryStoreExpirationState {
            startExpirationCountdown(date.addingTimeInterval(defaultExpirationPeriodInSeconds))
            countdownStartedByBackground = true
        }
    }

    /// The app is active again at `date`. Keys whose deadline passed while away expire
    /// now, before the next tick could show them. Otherwise a DiceKey still on screen
    /// defers expiration again, so leaving it later starts a full countdown.
    func appDidBecomeActive(at date: Date = Date()) {
        let startedByBackground = countdownStartedByBackground
        countdownStartedByBackground = false
        currentTime = date
        if case let .countdownInProgress(whenExpiring) = memoryStoreExpirationState, date > whenExpiring {
            expireAllKeys()
        } else if startedByBackground && !foregroundDiceKeyId.isEmpty {
            memoryStoreExpirationState = .countdownDeferred
        }
    }

    func clearForegroundDiceKey() {
        foregroundDiceKeyId = ""
        if case .countdownDeferred = memoryStoreExpirationState {
            startExpirationCountdown()
        }
    }
}
