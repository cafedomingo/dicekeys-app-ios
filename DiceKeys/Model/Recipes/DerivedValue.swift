//
//  DerivedValueView.swift
//  DiceKeys
//
//  Created by Angelos Veglektsis on 7/6/22.
//

import Derivation
import KeyFormats

enum DerivedValueView: Int, CaseIterable, Identifiable {
    case JSON
    case Password
    case Hex
    case HexSigningKey
    case HexUnsealing
    case HexSealing
    case BIP39
    case OpenPGPPrivateKey
    case OpenSSHPrivateKey
    case OpenSSHPublicKey

    var id: Int { self.rawValue }

    var description: String {
        switch self {
        case .JSON: return "JSON"
        case .Password: return "Password"
        case .Hex: return "HEX"
        case .HexSigningKey: return "HEX (Signing Key)"
        case .HexUnsealing: return "HEX (Unsealing Key)"
        case .HexSealing: return "HEX (Sealing Key)"
        case .BIP39: return "BIP39"
        case .OpenPGPPrivateKey: return "OpenPGP Private Key"
        case .OpenSSHPrivateKey: return "OpenSSH Private Key"
        case .OpenSSHPublicKey: return "OpenSSH Public Key"
        }
    }
}

protocol DerivedValue {
    var views: [DerivedValueView] { get }
    func valueForView(view: DerivedValueView) -> String
}

struct DerivedValuePassword: DerivedValue {
    let password: Password

    let views: [DerivedValueView] = [.Password, .JSON]

    func valueForView(view: DerivedValueView) -> String {
        switch view {
        case .Password: return password.password
        default: return password.toJson()
        }
    }
}

struct DerivedValueSecret: DerivedValue {
    let secret: Secret

    let views: [DerivedValueView]

    init(secret: Secret, showBIP39: Bool) {
        self.secret = secret
        views = showBIP39 ? [.JSON, .Hex, .BIP39] : [.JSON, .Hex]
    }

    func valueForView(view: DerivedValueView) -> String {
        switch view {
        case .Hex: return secret.bytes.asHexString
        case .BIP39:
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

    let views: [DerivedValueView] = [.JSON, .OpenPGPPrivateKey, .OpenSSHPrivateKey, .OpenSSHPublicKey, .HexSigningKey]

    init(signingKey: SigningKey) {
        self.signingKey = signingKey
        openPgpSecretKey = OpenPGP.secretKeyBlock(signingKey)
        openSshPrivateKey = OpenSSH.privateKeyPEM(signingKey)
        openSshPublicKey = OpenSSH.publicKeyLine(signingKey)
    }

    func valueForView(view: DerivedValueView) -> String {
        switch view {
        case .OpenPGPPrivateKey: return openPgpSecretKey
        case .OpenSSHPrivateKey: return openSshPrivateKey
        case .OpenSSHPublicKey: return openSshPublicKey
        case .HexSigningKey: return signingKey.signingKeyBytes.asHexString
        default: return signingKey.toJson()
        }
    }
}

struct DerivedValueSymmetricKey: DerivedValue {
    let symmetricKey: SymmetricKey

    let views: [DerivedValueView] = [.JSON, .Hex]

    func valueForView(view: DerivedValueView) -> String {
        switch view {
        case .Hex: return symmetricKey.keyBytes.asHexString
        default: return symmetricKey.toJson()
        }
    }
}

struct DerivedValueUnsealingKey: DerivedValue {
    let unsealingKey: UnsealingKey

    let views: [DerivedValueView] = [.JSON, .HexUnsealing, .HexSealing]

    func valueForView(view: DerivedValueView) -> String {
        switch view {
        case .HexUnsealing: return unsealingKey.unsealingKeyBytes.asHexString
        case .HexSealing: return unsealingKey.sealingKeyBytes.asHexString
        default: return unsealingKey.toJson()
        }
    }
}
