//
//  DerivableType+Descriptions.swift
//  DiceKeys
//

import Derivation

extension DerivableType {
    var description: String {
        switch self {
        case .password: return "Password"
        case .secret: return "Secret"
        case .signingKey: return "Signing Key"
        case .symmetricKey: return "Symmetric Key"
        case .unsealingKey: return "Unsealing Key"
        }
    }

    var descriptionForRecipeBuilder: String {
        switch self {
        case .password: return "password"
        case .secret: return "seed or other secret"
        case .signingKey: return "signing/authentication key"
        case .symmetricKey: return "symmetric cryptographic key"
        case .unsealingKey: return "public/private key pair"
        }
    }
}
