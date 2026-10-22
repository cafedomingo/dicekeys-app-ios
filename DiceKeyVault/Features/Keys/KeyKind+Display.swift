//
//  KeyKind+Display.swift
//  DiceKeyVault
//

import Derivation

extension KeyKind {
    /// Named by the tool the key feeds, spelled as that tool spells it.
    var title: String {
        switch self {
        case .ssh: "SSH"
        case .wireguard: "WireGuard"
        case .age: "age"
        case .passphrase: "Passphrase"
        case .wallet: "Wallet"
        }
    }

    var symbol: String {
        switch self {
        case .ssh: "terminal"
        case .wireguard: "network"
        case .age: "lock.doc"
        case .passphrase: "key"
        case .wallet: "list.number"
        }
    }

    /// A wallet's recovery phrase is shown to be written down, never copied or shared.
    var secretLeavesScreen: Bool { self != .wallet }

    var secretTitle: String {
        switch self {
        case .ssh, .wireguard: "Private key"
        case .age: "Private keys"
        case .passphrase: "Passphrase"
        case .wallet: "Recovery phrase"
        }
    }
}
