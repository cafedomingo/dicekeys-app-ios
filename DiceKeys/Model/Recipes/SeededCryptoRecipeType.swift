//
//  SeededCryptoRecipeType.swift
//  DiceKeys
//
//  The kinds of secret a recipe can derive. Lifted out of the former
//  Services/Api/SeededCryptoRecipeObject.swift when the request API was removed:
//  the recipe model and its UI need this type, the rest of that file was API-only.
//

import Foundation

enum SeededCryptoRecipeType: String, Codable, CaseIterable, Identifiable {
    case Password, Secret, SigningKey, SymmetricKey, UnsealingKey

    var id: String { rawValue }

    var description: String {
        switch self {
        case .Password: return "Password"
        case .Secret: return "Secret"
        case .SigningKey: return "Signing Key"
        case .SymmetricKey: return "Symmetric Key"
        case .UnsealingKey: return "Unsealing Key"
        }
    }

    var descriptionForRecipeBuilder: String {
        switch self {
        case .Password: return "password"
        case .Secret: return "seed or other secret"
        case .SigningKey: return "signing/authentication key"
        case .SymmetricKey: return "symmetric cryptographic key"
        case .UnsealingKey: return "public/private key pair"
        }
    }
}
