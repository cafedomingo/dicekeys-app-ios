//
//  SavedDiceKeysTests.swift
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

/// Serialized because every test here works on the one keychain item for `DiceKey.example`:
/// run in parallel, the deletes in one test pull the item out from under another.
@MainActor
@Suite(.serialized)
struct SavedDiceKeysTests {
    private let diceKey = DiceKey.example
    private let saved = SavedDiceKeys()

    /// The keychain outlives the test run, so each test starts and ends without the item.
    init() { try? saved.delete(id: diceKey.id) }

    @Test("a saved DiceKey is reported as saved, and deleting it removes the item")
    func savedKeyIsFoundAndCanBeDeleted() throws {
        #expect(!saved.contains(id: diceKey.id))

        try saved.save(diceKey)
        #expect(saved.contains(id: diceKey.id))
        #expect(SavedDiceKeys().contains(id: diceKey.id))

        // A delete whose query named a protection attribute the item does not carry would
        // silently match nothing, leaving the DiceKey saved.
        try saved.delete(id: diceKey.id)
        #expect(!saved.contains(id: diceKey.id))
        #expect(!SavedDiceKeys().contains(id: diceKey.id))
    }

    @Test("saving a DiceKey that is already saved replaces it instead of failing")
    func savingTwiceReplacesTheItem() throws {
        defer { try? saved.delete(id: diceKey.id) }
        try saved.save(diceKey)
        try saved.save(diceKey)
        #expect(SavedDiceKeys().contains(id: diceKey.id))
    }

    /// Saved items outlive app versions: an item is the DiceKey's 75-character text, named
    /// by its id, and both are pinned here as literals.
    @Test("a saved item reads back as the DiceKey its name says")
    func savedItemFormat() throws {
        let text = "A1tB2rC3bD4lE5tF6rG1bH2lI3tJ4rK5bL6lM1tN2rO3bP4lR5tS6rT1bU2lV3tW4rX5bY6lZ1t"
        let read = try SavedDiceKeys.diceKey(from: Data(text.utf8), id: "FDWCWOqOuLX6kRVI9K31_A")
        #expect(read.humanReadableForm == diceKey.humanReadableForm)
    }

    @Test("an item holding a different DiceKey than its name says is refused, not unlocked")
    func mismatchedItemIsRefused() throws {
        let other = try DiceKey(humanReadableForm: "B2rA1t" + diceKey.humanReadableForm.dropFirst(6))
        #expect(throws: SavedDiceKeys.Mismatch.self) {
            try SavedDiceKeys.diceKey(from: Data(other.humanReadableForm.utf8), id: diceKey.id)
        }
    }

    @Test("the saved DiceKey is stored behind an access control")
    func savedKeyCarriesAnAccessControl() throws {
        defer { try? saved.delete(id: diceKey.id) }
        try saved.save(diceKey)

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
        let expectedAccessControl = try #require(
            SecAccessControlCreateWithFlags(
                nil, kSecAttrAccessibleWhenUnlockedThisDeviceOnly, .userPresence, nil
            ))
        #expect(CFEqual(storedAccessControl, expectedAccessControl))

        // The DiceKey must not be readable while the device is locked, nor restorable onto
        // another device.
        #expect(
            attributes[kSecAttrAccessible as String] as? String == kSecAttrAccessibleWhenUnlockedThisDeviceOnly
                as String)
    }
}
