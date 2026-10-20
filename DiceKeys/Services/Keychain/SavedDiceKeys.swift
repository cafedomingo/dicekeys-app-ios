//
//  SavedDiceKeys.swift
//  DiceKeys
//

import Foundation
import LocalAuthentication
import Observation

/// DiceKeys saved on this device, readable only by this app, behind Face ID, Touch ID or
/// the passcode. Never synced and never restored onto another device.
@MainActor @Observable
final class SavedDiceKeys {
    /// Cached so views can ask on every render without a keychain call each time; ignored
    /// by observation because it fills in during rendering. `revision` is what views watch.
    @ObservationIgnored private var isSaved: [String: Bool] = [:]
    private var revision = 0

    /// When the keychain can't say (the device is locked, say), the answer is "saved", so a
    /// saved DiceKey is never hidden; only a definite answer is remembered.
    func contains(id: String) -> Bool {
        _ = revision
        if let saved = isSaved[id] { return saved }
        guard let saved = Keychain.contains(id: id) else { return true }
        isSaved[id] = saved
        return saved
    }

    func save(_ diceKey: DiceKey) throws {
        try Keychain.save(Data(diceKey.humanReadableForm.utf8), id: diceKey.id)
        changed(id: diceKey.id, saved: true)
    }

    func delete(id: String) throws {
        try Keychain.delete(id: id)
        changed(id: id, saved: false)
    }

    /// Asks for Face ID, Touch ID or the passcode, then reads the DiceKey.
    func load(id: String, name: String) async throws -> DiceKey {
        let context = LAContext()
        var policyError: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &policyError) else {
            throw policyError ?? LAError(.passcodeNotSet)
        }
        guard try await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: "Unlock \(name)") else {
            throw LAError(.authenticationFailed)
        }
        let data = try Keychain.load(id: id, context: context)
        return try DiceKey(humanReadableForm: String(decoding: data, as: UTF8.self))
    }

    private func changed(id: String, saved: Bool) {
        isSaved[id] = saved
        revision += 1
    }
}

/// Generic-password items in the data protection keychain, named by the DiceKey's id.
private enum Keychain {
    enum KeychainError: Error {
        case notFound
        case osError(OSStatus)
        case couldNotCreateAccessControl
    }

    /// The attributes that name an item, and nothing more. A query naming the item's
    /// protection as well would match only items protected in exactly that way, and a
    /// delete matching nothing fails silently.
    private static func query(id: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: id,
            kSecUseDataProtectionKeychain as String: true
        ]
    }

    /// Requires the user's presence to read the item back, enforced by the keychain rather
    /// than by app code a caller could skip. The access control carries the protection
    /// class, so `kSecAttrAccessible` is not set separately.
    private static func userPresenceAccessControl() throws -> SecAccessControl {
        guard
            let accessControl = SecAccessControlCreateWithFlags(
                nil, kSecAttrAccessibleWhenUnlockedThisDeviceOnly, .userPresence, nil)
        else { throw KeychainError.couldNotCreateAccessControl }
        return accessControl
    }

    static func delete(id: String) throws {
        let status = SecItemDelete(query(id: id) as CFDictionary)
        if status != errSecSuccess && status != errSecItemNotFound {
            throw KeychainError.osError(status)
        }
    }

    /// Adds before deleting, so a failed add leaves an unsaved keychain untouched. On a
    /// duplicate the old item holds this same DiceKey, since the account is its id.
    static func save(_ data: Data, id: String) throws {
        var attributes = query(id: id)
        attributes[kSecAttrAccessControl as String] = try userPresenceAccessControl()
        attributes[kSecValueData as String] = data
        var status = SecItemAdd(attributes as CFDictionary, nil)
        if status == errSecDuplicateItem {
            try delete(id: id)
            status = SecItemAdd(attributes as CFDictionary, nil)
        }
        if status != errSecSuccess {
            throw KeychainError.osError(status)
        }
    }

    /// Asked without the data and with interaction forbidden, so it never prompts. Nil when
    /// the answer is unknown: an item needing authentication, or the device being locked.
    static func contains(id: String) -> Bool? {
        let context = LAContext()
        context.interactionNotAllowed = true
        var itemQuery = query(id: id)
        itemQuery[kSecUseAuthenticationContext as String] = context
        switch SecItemCopyMatching(itemQuery as CFDictionary, nil) {
        case errSecSuccess: return true
        case errSecItemNotFound: return false
        default: return nil
        }
    }

    /// Reuses the already-authenticated context, sparing the user a second prompt.
    static func load(id: String, context: LAContext) throws -> Data {
        var itemQuery = query(id: id)
        itemQuery[kSecReturnData as String] = true
        itemQuery[kSecUseAuthenticationContext as String] = context
        var item: CFTypeRef?
        let status = SecItemCopyMatching(itemQuery as CFDictionary, &item)
        switch status {
        case errSecSuccess:
            guard let data = item as? Data else { throw KeychainError.notFound }
            return data
        case errSecItemNotFound:
            throw KeychainError.notFound
        default:
            throw KeychainError.osError(status)
        }
    }
}

extension Error {
    /// The user, or the system, canceled an authentication prompt: not worth reporting.
    var isAuthenticationCancellation: Bool {
        guard let laError = self as? LAError else { return false }
        switch laError.code {
        case .userCancel, .appCancel, .systemCancel, .userFallback: return true
        default: return false
        }
    }
}
