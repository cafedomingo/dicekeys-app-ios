//
//  DiceKeyKeychainTests.swift
//  DiceKeysTests
//
//  Reading a saved DiceKey back needs Face ID, Touch ID or the passcode, so it cannot be
//  tested without a person. These cover everything around the read: that saving succeeds,
//  that asking whether a DiceKey is saved answers truthfully, and that deleting removes the
//  item. A prompt raised by any of them would hang the test rather than pass it.
//

import Foundation
import LocalAuthentication
import Security
import Testing
@testable import DiceKeys

/// Serialized because every test here works on the one keychain item for `DiceKey.Example`:
/// run in parallel, the deletes in one test pull the item out from under another.
@Suite(.serialized)
struct DiceKeyKeychainTests {
    /// The keychain outlives a test run, so each test starts by clearing its own item.
    private func makeKeychain(forKeyId keyId: String) -> DiceKeyKeychain {
        let keychain = DiceKeyKeychain()
        try? keychain.delete(keyId: keyId)
        return keychain
    }

    @Test("a saved DiceKey is reported as saved, and deleting it removes the item")
    func savedKeyIsFoundAndCanBeDeleted() throws {
        let diceKey = DiceKey.Example
        let keychain = makeKeychain(forKeyId: diceKey.id)
        #expect(!keychain.hasDiceKey(forKeyId: diceKey.id))

        try keychain.put(diceKey: diceKey)
        #expect(keychain.hasDiceKey(forKeyId: diceKey.id))

        // A delete whose query named a protection attribute the item no longer carries
        // would silently match nothing, leaving the DiceKey saved.
        try keychain.delete(keyId: diceKey.id)
        #expect(!keychain.hasDiceKey(forKeyId: diceKey.id))
    }

    @Test("saving a DiceKey that is already saved replaces it instead of failing")
    func savingTwiceReplacesTheItem() throws {
        let diceKey = DiceKey.Example
        let keychain = makeKeychain(forKeyId: diceKey.id)
        defer { try? keychain.delete(keyId: diceKey.id) }

        try keychain.put(diceKey: diceKey)
        // The second save takes the duplicate path: add, then remove the old item and add again.
        try keychain.put(diceKey: diceKey)
        #expect(keychain.hasDiceKey(forKeyId: diceKey.id))
    }

    @Test("a DiceKey that was never saved is reported as not saved")
    func unsavedKeyIsNotFound() throws {
        let diceKey = DiceKey.Example
        let keychain = makeKeychain(forKeyId: diceKey.id)
        #expect(!keychain.hasDiceKey(forKeyId: diceKey.id))
    }

    @Test("the saved DiceKey is stored behind an access control")
    func savedKeyCarriesAnAccessControl() throws {
        let diceKey = DiceKey.Example
        let keychain = makeKeychain(forKeyId: diceKey.id)
        defer { try? keychain.delete(keyId: diceKey.id) }
        try keychain.put(diceKey: diceKey)

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: diceKey.id,
            kSecUseDataProtectionKeychain as String: true,
            kSecReturnAttributes as String: true
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        #expect(status == errSecSuccess)
        let attributes = item as? [String: Any]
        // `SecAccessControl` compares by its constraints, and one created with no flags is
        // still non-nil while demanding nothing, so check the constraints themselves.
        let storedAccessControl = try #require(attributes?[kSecAttrAccessControl as String]) as AnyObject
        let expectedAccessControl = try #require(SecAccessControlCreateWithFlags(
            nil, kSecAttrAccessibleWhenUnlockedThisDeviceOnly, .userPresence, nil
        ))
        #expect(CFEqual(storedAccessControl, expectedAccessControl))
        // The DiceKey must not be readable while the device is locked, nor restorable onto
        // another device.
        #expect(attributes?[kSecAttrAccessible as String] as? String == kSecAttrAccessibleWhenUnlockedThisDeviceOnly as String)
    }
}
