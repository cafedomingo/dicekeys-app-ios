//
//  AppInfo.swift
//  DiceKeys
//

import Foundation

/// What the app says about itself, in About and wherever its name appears.
enum AppInfo {
    static let name = "DiceKey Vault"
    static let diceKeysSite = URL(string: "https://dicekeys.com")!
    static let credits = [
        "The derivation's design follows seeded-crypto, by DiceKeys, LLC, under the MIT License",
        "Inconsolata, by Raph Levien, under the SIL Open Font License 1.1",
        "The EFF Large Wordlist, by the Electronic Frontier Foundation, under CC BY 4.0",
        "The BIP39 English word list, under the MIT License"
    ]

    static var version: String {
        Bundle.main.object(forInfoDictionaryKey: versionKey) as? String ?? ""
    }
    private static let versionKey = "CFBundleShortVersionString"
}
