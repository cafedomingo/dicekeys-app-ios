//
//  ScannedCode.swift
//  DiceKeys
//

import Foundation

/// A code the scan screen read: a list card's link or a recovery sheet's code.
enum ScannedCode: Equatable {
    case list(CatalogFile)
    case recovery(RecoveryCode)

    /// A list card's link or a recovery sheet's code, readable or not.
    static func isOwn(_ payload: String) -> Bool {
        payload.hasPrefix(RecoveryCode.prefix) || payload.hasPrefix(CatalogFile.urlScheme + ":")
    }

    /// Nil for a code that isn't this app's, so a stray QR code in view is ignored; throws for
    /// one of this app's codes that can't be read, such as one from a newer version.
    init?(payload: String) throws {
        guard Self.isOwn(payload) else { return nil }
        if payload.hasPrefix(RecoveryCode.prefix) {
            self = .recovery(try RecoveryCode(payload: payload))
        } else {
            guard let url = URL(string: payload) else { throw CatalogFile.Failure.notACatalog }
            self = .list(try CatalogFile(importURL: url))
        }
    }
}
