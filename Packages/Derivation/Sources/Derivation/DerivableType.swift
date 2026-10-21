//
//  DerivableType.swift
//  Derivation
//

/// What the derived bytes become. The raw value is hashed in front of the recipe's text, so
/// it keeps one recipe's keys apart and cannot change.
public enum DerivableType: String, Sendable {
    case ed25519
    case x25519
    case passphrase
    case bip39
    /// An age key's post-quantum identity: the X-Wing seed.
    case mlkem768x25519
    /// A DiceKey's id, which has no recipe.
    case diceKeyID = "dicekey-id"
}
