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
    }

    static func deleteKey(id: String, throwIfFails: Bool = false) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: id,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
            kSecUseDataProtectionKeychain as String: true
        ]

        let status = SecItemDelete(query as CFDictionary)
        if status != errSecSuccess && status != errSecItemNotFound && throwIfFails {
            throw KeyChainError.osError(status)
        }
    }

    static func saveKey(id: String, key: Data) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: id,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
            kSecUseDataProtectionKeychain as String: true,
            kSecValueData as String: key
        ]

        try deleteKey(id: id)

        let status = SecItemAdd(query as CFDictionary, nil)
        if status != errSecSuccess {
            throw KeyChainError.osError(status)
        }
    }

    static func saveKey(id: String, key: String) throws {
        try saveKey(id: id, key: Data(key.utf8))
    }

    static func isPresentInKeyChain(id: String) -> Bool {
        // Seek a generic password with the given account.
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: id,
            kSecUseDataProtectionKeychain as String: true
        ]

        // Only a definite "not found" means absent. Other failures (errSecInteractionNotAllowed
        // while protected data is unavailable, for one) say nothing about the item, and
        // reporting a saved DiceKey as unsaved would invite a re-save or hide it.
        return SecItemCopyMatching(query as CFDictionary, nil) != errSecItemNotFound
    }

    static func loadKeyData(id: String) throws -> Data {
        // Seek a generic password with the given account.
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: id,
            kSecUseDataProtectionKeychain as String: true,
            kSecReturnData as String: true
        ]

        // Find and cast the result as data.
        var item: CFTypeRef?

        let status = SecItemCopyMatching(query as CFDictionary, &item)
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

    static func loadKeyString(id: String) throws -> String {
        String(decoding: try loadKeyData(id: id), as: UTF8.self)
    }
}

private let defaultReason: String = "Unlock your DiceKey"

/// Stores raw DiceKeys as password credentials in the Apple KeyChain, for use
/// only by this app on this device, behind Face ID / Touch ID / passcode.
/// Stateless; `AppModel` owns the instance the stores share.
struct DiceKeyKeychain: Sendable {

    init() {}

    func getReason(forCenterFace centerFace: Face?) -> String {
        if let face = centerFace {
            return "Unlock DiceKey with \(face.letterAndDigit) in Center"
        }
        return defaultReason
    }

    /// Asks the user to authenticate with Face ID, Touch ID, or their passcode.
    /// Throws an `LAError` (or the error reported by `canEvaluatePolicy`) on failure.
    func authenticate(reason: String? = nil) async throws {
        let laContext = LAContext()
        var policyError: NSError?
        guard laContext.canEvaluatePolicy(.deviceOwnerAuthentication, error: &policyError) else {
            throw policyError ?? LAError(.passcodeNotSet)
        }
        let success = try await laContext.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason ?? defaultReason)
        guard success else {
            throw LAError(.authenticationFailed)
        }
    }

    /// Authenticates the user and then reads the DiceKey from the keychain.
    func getDiceKey(fromKeyId keyId: String, centerFace: Face? = nil) async throws -> DiceKey {
        try await authenticate(reason: getReason(forCenterFace: centerFace))
        let diceKeyInHRF = try KeyChain.loadKeyString(id: keyId)
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
