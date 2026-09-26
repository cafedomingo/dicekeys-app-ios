//
//  UnlockedDiceKeyState.swift
//  DiceKeys
//
//  Created by Stuart Schechter on 2020/12/01.
//

import Observation

/// Observable state for a DiceKey that is unlocked in memory: the key itself and
/// whether it is saved (encrypted) in the keychain. Created and cached by
/// `DiceKeyMemoryStore`.
@MainActor @Observable
final class UnlockedDiceKeyState: Identifiable {
    let diceKey: DiceKey
    let keyId: String

    @ObservationIgnored private let knownDiceKeysStore: KnownDiceKeysStore
    @ObservationIgnored private let keychain: DiceKeyKeychain

    /// The most recent keychain failure, for the UI to surface. Cleared when a
    /// later operation succeeds.
    private(set) var lastError: PresentableError?

    /// Mirrors the keychain. Setting it saves or deletes the DiceKey; failures
    /// land in `lastError` and leave the value unchanged.
    var isDiceKeyStored: Bool {
        get { isDiceKeyStoredCache }
        set { setStored(newValue) }
    }
    private var isDiceKeyStoredCache: Bool

    nonisolated var id: String { keyId }

    var nickname: String { diceKey.nickname }

    init(diceKey: DiceKey, knownDiceKeysStore: KnownDiceKeysStore, keychain: DiceKeyKeychain) {
        self.diceKey = diceKey
        self.knownDiceKeysStore = knownDiceKeysStore
        self.keychain = keychain
        let keyId = diceKey.id
        self.keyId = keyId
        self.isDiceKeyStoredCache = keychain.hasDiceKey(forKeyId: keyId)
    }

    private func setStored(_ stored: Bool) {
        do {
            if stored {
                try keychain.put(diceKey: diceKey)
                // Currently we store the center face IFF we store the DiceKey
                knownDiceKeysStore.addKnownDiceKey(
                    keyId: keyId,
                    centerFaceInHumanReadableForm: diceKey.centerFace.humanReadableForm
                )
            } else {
                try keychain.delete(keyId: keyId)
                knownDiceKeysStore.removeKnownDiceKey(keyId: keyId)
            }
            lastError = nil
        } catch {
            lastError = PresentableError(title: stored ? "Couldn't Save DiceKey" : "Couldn't Remove DiceKey", error: error)
        }
        isDiceKeyStoredCache = keychain.hasDiceKey(forKeyId: keyId)
    }
}
