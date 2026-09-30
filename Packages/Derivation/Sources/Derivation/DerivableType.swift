//
//  DerivableType.swift
//  Derivation
//

/// The kinds of value a recipe can derive. The raw values are the `type` strings of the
/// recipe format and of the JSON the derived values print, so they cannot change.
public enum DerivableType: String, Codable, CaseIterable, Identifiable, Sendable {
    case password = "Password"
    case secret = "Secret"
    case signingKey = "SigningKey"
    case symmetricKey = "SymmetricKey"
    case unsealingKey = "UnsealingKey"

    public var id: String { rawValue }
}
