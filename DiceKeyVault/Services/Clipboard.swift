//
//  Clipboard.swift
//  DiceKeyVault
//

import UIKit

enum Clipboard {
    /// How long a copied secret stays on the clipboard.
    static let secretLifetime: TimeInterval = 60

    /// Public text, such as a public key: shared like any other copy.
    static func copy(_ text: String) {
        UIPasteboard.general.string = text
    }

    /// Kept off Universal Clipboard, and cleared by the system after `secretLifetime`.
    static func copySecret(_ text: String) {
        UIPasteboard.general.setItems(
            [[UIPasteboard.typeAutomatic: text]],
            options: [.localOnly: true, .expirationDate: Date.now.addingTimeInterval(secretLifetime)])
    }
}
