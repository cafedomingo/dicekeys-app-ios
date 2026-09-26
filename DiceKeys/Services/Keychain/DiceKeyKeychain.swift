//
//  DiceKeyKeychain.swift
//  DiceKeys
//
//  Created by Stuart Schechter on 2020/11/28.
//

import Foundation
import LocalAuthentication

/// A set of functions to simplify storing strings in the Apple KeyChain
/// such that only this app on this device can read them.
private enum KeyChain {
    enum KeyChainError: Error {
        case notFound
        case osError(OSStatus)
        case couldNotCreateAccessControl((any Error)?)
    }

    /// The attributes that name an item, and nothing more. Lookups and deletes use only
    /// these, so they match both the items written now (which carry `kSecAttrAccessControl`)
    /// and any an older build left behind (which carried `kSecAttrAccessible` instead).
    /// Naming a protection attribute in a query risks matching nothing, which for a delete
    /// is a silent no-op.
    private static func query(id: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: id,
            kSecUseDataProtectionKeychain as String: true
        ]
    }

    /// Requires the user's presence (Face ID, Touch ID or the passcode) to read the item
    /// back, enforced by the keychain itself rather than by a call to `authenticate()` that
    /// a future caller could forget. The protection class moves into the access control
    /// object, so it is no longer passed separately as `kSecAttrAccessible`.
    private static func userPresenceAccessControl() throws -> SecAccessControl {
        var error: Unmanaged<CFError>?
        guard let accessControl = SecAccessControlCreateWithFlags(
            nil,
            kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
            .userPresence,
            &error
        ) else {
            throw KeyChainError.couldNotCreateAccessControl(error?.takeRetainedValue())
        }
        return accessControl
    }

    static func deleteKey(id: String, throwIfFails: Bool = false) throws {
        let status = SecItemDelete(query(id: id) as CFDictionary)
        if status != errSecSuccess && status != errSecItemNotFound && throwIfFails {
            throw KeyChainError.osError(status)
        }
    }

    static func saveKey(id: String, key: Data) throws {
        var attributes = query(id: id)
        attributes[kSecAttrAccessControl as String] = try userPresenceAccessControl()
        attributes[kSecValueData as String] = key

        // Add first, so a save that fails cannot leave the keychain with nothing. Only a
        // duplicate needs the old item removed, and that old item holds this same DiceKey:
        // the account is `DiceKey.id`, which is derived by hashing the key itself.
        var status = SecItemAdd(attributes as CFDictionary, nil)
        if status == errSecDuplicateItem {
            try deleteKey(id: id, throwIfFails: true)
            status = SecItemAdd(attributes as CFDictionary, nil)
        }
        if status != errSecSuccess {
            throw KeyChainError.osError(status)
        }
    }

    static func saveKey(id: String, key: String) throws {
        try saveKey(id: id, key: Data(key.utf8))
    }

    static func isPresentInKeyChain(id: String) -> Bool {
        // Seek a generic password with the given account, without asking for its data and
        // with interaction forbidden outright, so that merely checking whether a DiceKey is
        // saved can never raise a Face ID prompt. This runs on the main path: from
        // `UnlockedDiceKeyState.init`, and again after every save or delete.
        let context = LAContext()
        context.interactionNotAllowed = true

        var itemQuery = query(id: id)
        itemQuery[kSecUseAuthenticationContext as String] = context

        // Only a definite "not found" means absent. Other failures (errSecInteractionNotAllowed
        // for an item that would need authenticating, or while protected data is unavailable)
        // say nothing about the item, and reporting a saved DiceKey as unsaved would invite a
        // re-save or hide it.
        return SecItemCopyMatching(itemQuery as CFDictionary, nil) != errSecItemNotFound
    }

    static func loadKeyData(id: String, context: LAContext) throws -> Data {
        // Seek a generic password with the given account, and ask for its data.
        var itemQuery = query(id: id)
        itemQuery[kSecReturnData as String] = true
        // Reuse the context the caller has already authenticated, so that reading an
        // access-controlled item does not prompt the user a second time.
        itemQuery[kSecUseAuthenticationContext as String] = context

        // Find and cast the result as data.
        var item: CFTypeRef?

        let status = SecItemCopyMatching(itemQuery as CFDictionary, &item)
        switch status {
        case errSecSuccess:
            guard let data = item as? Data else { throw KeyChainError.notFound }
            return data
        case errSecItemNotFound:
            throw KeyChainError.notFound
        default:
            throw KeyChainError.osError(status)
        }
    }

    static func loadKeyString(id: String, context: LAContext) throws -> String {
        String(decoding: try loadKeyData(id: id, context: context), as: UTF8.self)
    }
}

private let defaultReason: String = "Unlock your DiceKey"

/// Stores raw DiceKeys as password credentials in the Apple KeyChain, for use
/// only by this app on this device, behind Face ID / Touch ID / passcode.
/// Stateless; `AppModel` owns the instance the stores share.
struct DiceKeyKeychain: Sendable {
    func getReason(forCenterFace centerFace: Face?) -> String {
        if let face = centerFace {
            return "Unlock DiceKey with \(face.letterAndDigit) in Center"
        }
        return defaultReason
    }

    /// Asks the user to authenticate with Face ID, Touch ID, or their passcode, and returns
    /// the satisfied context so the keychain read that follows can reuse it.
    /// Throws an `LAError` (or the error reported by `canEvaluatePolicy`) on failure.
    func authenticate(reason: String? = nil) async throws -> LAContext {
        let laContext = LAContext()
        var policyError: NSError?
        guard laContext.canEvaluatePolicy(.deviceOwnerAuthentication, error: &policyError) else {
            throw policyError ?? LAError(.passcodeNotSet)
        }
        let success = try await laContext.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason ?? defaultReason)
        guard success else {
            throw LAError(.authenticationFailed)
        }
        return laContext
    }

    /// Authenticates the user and then reads the DiceKey from the keychain.
    func getDiceKey(fromKeyId keyId: String, centerFace: Face? = nil) async throws -> DiceKey {
        let context = try await authenticate(reason: getReason(forCenterFace: centerFace))
        let diceKeyInHRF = try KeyChain.loadKeyString(id: keyId, context: context)
        return try DiceKey.createFrom(humanReadableForm: diceKeyInHRF)
    }

    func delete(keyId: String) throws {
        try KeyChain.deleteKey(id: keyId, throwIfFails: true)
    }

    func hasDiceKey(forKeyId keyId: String) -> Bool {
        KeyChain.isPresentInKeyChain(id: keyId)
    }

    /// Stores the DiceKey and returns its id.
    @discardableResult
    func put(diceKey: DiceKey) throws -> String {
        let keyId = diceKey.id
        try KeyChain.saveKey(id: keyId, key: diceKey.toHumanReadableForm())
        return keyId
    }
}

extension Error {
    /// True when the user (or the system) cancelled an authentication prompt,
    /// which is not worth reporting as an error.
    var isAuthenticationCancellation: Bool {
        guard let laError = self as? LAError else { return false }
        switch laError.code {
        case .userCancel, .appCancel, .systemCancel, .userFallback:
            return true
        default:
            return false
        }
    }
}
