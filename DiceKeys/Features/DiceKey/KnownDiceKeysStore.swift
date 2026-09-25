//
//  KnownDiceKeysStore.swift
//  DiceKeys
//
//  Created by Stuart Schechter on 2021/02/07.
//

import Foundation
import Observation

/// What the app remembers about a DiceKey whose dice are stored encrypted in the
/// keychain: its id and (optionally) its center face, so the home screen can
/// show which DiceKey to unlock.
struct StoredEncryptedDiceKeyMetadata: Identifiable, Hashable, Sendable {
    let keyId: String
    let centerFaceInHumanReadableForm: String
    /// Whether the 25 dice are still present in the keychain.
    let isDiceKeyStored: Bool

    var id: String { keyId }

    var centerFace: Face? {
        centerFaceInHumanReadableForm.count < 3 ? nil : try? Face(fromHumanReadableForm: centerFaceInHumanReadableForm)
    }

    var nickname: String {
        guard let centerFace else { return "Unknown DiceKey" }
        return nicknameForDiceKey(centerFace: centerFace)
    }
}

/// Persists (in `UserDefaults`) the list of DiceKey ids that have been saved to
/// the keychain, plus the center face of each so it can be shown before unlocking.
@MainActor @Observable
final class KnownDiceKeysStore {
    private static let knownDiceKeysFieldName = "knownDiceKeys"

    /// The UserDefaults key format is unchanged from earlier versions so that
    /// existing installs keep their data.
    private static func centerFaceKey(forKeyId keyId: String) -> String {
        "keyId: '\(keyId)', field: 'centerFace'"
    }

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let keychain: DiceKeyKeychain

    private(set) var knownDiceKeys: [String] {
        didSet { defaults.set(knownDiceKeys, forKey: Self.knownDiceKeysFieldName) }
    }

    /// keyId -> center face in human-readable form ("" when not stored).
    private var centerFacesByKeyId: [String: String] = [:]

    init(defaults: UserDefaults = .standard, keychain: DiceKeyKeychain) {
        self.defaults = defaults
        self.keychain = keychain
        let knownDiceKeys = defaults.stringArray(forKey: Self.knownDiceKeysFieldName) ?? []
        self.knownDiceKeys = knownDiceKeys
        for keyId in knownDiceKeys {
            centerFacesByKeyId[keyId] = defaults.string(forKey: Self.centerFaceKey(forKeyId: keyId)) ?? ""
        }
    }

    func addKnownDiceKey(keyId: String, centerFaceInHumanReadableForm: String?) {
        if !knownDiceKeys.contains(keyId) {
            knownDiceKeys.append(keyId)
        }
        setCenterFace(centerFaceInHumanReadableForm, forKeyId: keyId)
    }

    func removeKnownDiceKey(keyId: String) {
        knownDiceKeys.removeAll { $0 == keyId }
        setCenterFace(nil, forKeyId: keyId)
    }

    func setCenterFace(_ humanReadableForm: String?, forKeyId keyId: String) {
        let value = humanReadableForm ?? ""
        centerFacesByKeyId[keyId] = value
        defaults.set(value, forKey: Self.centerFaceKey(forKeyId: keyId))
    }

    func metadata(forKeyId keyId: String) -> StoredEncryptedDiceKeyMetadata {
        StoredEncryptedDiceKeyMetadata(
            keyId: keyId,
            centerFaceInHumanReadableForm: centerFacesByKeyId[keyId] ?? "",
            isDiceKeyStored: keychain.hasDiceKey(forKeyId: keyId)
        )
    }

    /// Metadata for every known DiceKey whose dice can still be read from the keychain.
    var storedDiceKeys: [StoredEncryptedDiceKeyMetadata] {
        knownDiceKeys
            .map { metadata(forKeyId: $0) }
            .filter { $0.isDiceKeyStored }
            .sorted { $0.centerFaceInHumanReadableForm < $1.centerFaceInHumanReadableForm }
    }
}
