//
//  DerivedValueView.swift
//  DiceKeys
//

import Derivation
import KeyFormats

enum DerivedValueView: Int, CaseIterable, Identifiable {
    case json
    case password
    case hex
    case hexSigningKey
    case hexUnsealing
    case hexSealing
    case bip39
    case openPGPPrivateKey
    case openSSHPrivateKey
    case openSSHPublicKey

    var id: Int { self.rawValue }

    var description: String {
        switch self {
        case .json: return "JSON"
        case .password: return "Password"
        case .hex: return "HEX"
        case .hexSigningKey: return "HEX (Signing Key)"
        case .hexUnsealing: return "HEX (Unsealing Key)"
        case .hexSealing: return "HEX (Sealing Key)"
        case .bip39: return "BIP39"
        case .openPGPPrivateKey: return "OpenPGP Private Key"
        case .openSSHPrivateKey: return "OpenSSH Private Key"
        case .openSSHPublicKey: return "OpenSSH Public Key"
        }
    }
}

protocol DerivedValue {
    var views: [DerivedValueView] { get }
    func valueForView(view: DerivedValueView) -> String
}

struct DerivedValuePassword: DerivedValue {
    let password: Password

    let views: [DerivedValueView] = [.password, .json]

    func valueForView(view: DerivedValueView) -> String {
        switch view {
        case .password: return password.password
        default: return password.toJson()
        }
    }
}

struct DerivedValueSecret: DerivedValue {
    let secret: Secret

    let views: [DerivedValueView]

    init(secret: Secret, showBIP39: Bool) {
        self.secret = secret
        views = showBIP39 ? [.json, .hex, .bip39] : [.json, .hex]
    }

    func valueForView(view: DerivedValueView) -> String {
        switch view {
        case .hex: return secret.bytes.asHexString
        case .bip39:
            // Offered only for 32-byte secrets, which always have a mnemonic.
            return (try? BIP39.mnemonic(entropy: secret.bytes)) ?? secret.bytes.asHexString
        default: return secret.toJson()
        }
    }
}

struct DerivedValueSigningKey: DerivedValue {
    let signingKey: SigningKey
    let openPgpSecretKey: String
    let openSshPrivateKey: String
    let openSshPublicKey: String

    let views: [DerivedValueView] = [.json, .openPGPPrivateKey, .openSSHPrivateKey, .openSSHPublicKey, .hexSigningKey]

    init(signingKey: SigningKey) {
        self.signingKey = signingKey
        openPgpSecretKey = OpenPGP.secretKeyBlock(signingKey)
        openSshPrivateKey = OpenSSH.privateKeyPEM(signingKey)
        openSshPublicKey = OpenSSH.publicKeyLine(signingKey)
    }

    func valueForView(view: DerivedValueView) -> String {
        switch view {
        case .openPGPPrivateKey: return openPgpSecretKey
        case .openSSHPrivateKey: return openSshPrivateKey
        case .openSSHPublicKey: return openSshPublicKey
        case .hexSigningKey: return signingKey.signingKeyBytes.asHexString
        default: return signingKey.toJson()
        }
    }
}

struct DerivedValueSymmetricKey: DerivedValue {
    let symmetricKey: SymmetricKey

    let views: [DerivedValueView] = [.json, .hex]

    func valueForView(view: DerivedValueView) -> String {
        switch view {
        case .hex: return symmetricKey.keyBytes.asHexString
        default: return symmetricKey.toJson()
        }
    }
}

struct DerivedValueUnsealingKey: DerivedValue {
    let unsealingKey: UnsealingKey

    let views: [DerivedValueView] = [.json, .hexUnsealing, .hexSealing]

    func valueForView(view: DerivedValueView) -> String {
        switch view {
        case .hexUnsealing: return unsealingKey.unsealingKeyBytes.asHexString
        case .hexSealing: return unsealingKey.sealingKeyBytes.asHexString
        default: return unsealingKey.toJson()
        }
    }
}
