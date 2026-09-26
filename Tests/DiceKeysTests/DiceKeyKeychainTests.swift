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
import Security
import Testing
@testable import DiceKeys

/// Serialized because every test here works on the one keychain item for `DiceKey.Example`:
/// run in parallel, the deletes in one test pull the item out from under another.
@Suite(.serialized)
final class DiceKeyKeychainTests {
    private let diceKey = DiceKey.Example
    private let keychain = DiceKeyKeychain()

    /// The keychain outlives the test run, so clear the item on the way in and on the way out.
    init() { try? keychain.delete(keyId: diceKey.id) }
    deinit { try? keychain.delete(keyId: diceKey.id) }

    @Test("a saved DiceKey is reported as saved, and deleting it removes the item")
    func savedKeyIsFoundAndCanBeDeleted() throws {
        #expect(!keychain.hasDiceKey(forKeyId: diceKey.id))

        try keychain.put(diceKey: diceKey)
        #expect(keychain.hasDiceKey(forKeyId: diceKey.id))

        // A delete whose query named a protection attribute the item does not carry would
        // silently match nothing, leaving the DiceKey saved.
        try keychain.delete(keyId: diceKey.id)
        #expect(!keychain.hasDiceKey(forKeyId: diceKey.id))
    }

    @Test("saving a DiceKey that is already saved replaces it instead of failing")
    func savingTwiceReplacesTheItem() throws {
        try keychain.put(diceKey: diceKey)
        try keychain.put(diceKey: diceKey)
        #expect(keychain.hasDiceKey(forKeyId: diceKey.id))
    }

    @Test("the saved DiceKey is stored behind an access control")
    func savedKeyCarriesAnAccessControl() throws {
        try keychain.put(diceKey: diceKey)

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: diceKey.id,
            kSecUseDataProtectionKeychain as String: true,
            kSecReturnAttributes as String: true
        ]
        var item: CFTypeRef?
        #expect(SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess)
        let attributes = try #require(item as? [String: Any])

        // `SecAccessControl` compares by its constraints, and one created with no flags is
        // still non-nil while demanding nothing, so check the constraints themselves.
        let storedAccessControl = try #require(attributes[kSecAttrAccessControl as String]) as AnyObject
        let expectedAccessControl = try #require(SecAccessControlCreateWithFlags(
            nil, kSecAttrAccessibleWhenUnlockedThisDeviceOnly, .userPresence, nil
        ))
        #expect(CFEqual(storedAccessControl, expectedAccessControl))

        // The DiceKey must not be readable while the device is locked, nor restorable onto
        // another device.
        #expect(attributes[kSecAttrAccessible as String] as? String == kSecAttrAccessibleWhenUnlockedThisDeviceOnly as String)
    }
}
