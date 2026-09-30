//
//  KeyFormatsTests.swift
//  DerivationTests
//

import Foundation
import Testing
import Derivation
import KeyFormats

@Suite("BIP39")
struct BIP39Tests {
    static let vectors: [(entropyHex: String, mnemonic: String)] = [
        ("00000000000000000000000000000000",
         "abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about"),
        ("7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f",
         "legal winner thank year wave sausage worth useful legal winner thank yellow"),
        ("066dca1a2bb7e8a1db2832148ce9933eea0f3ac9548d793112d9a95c9407efad",
         "all hour make first leader extend hole alien behind guard gospel lava path output census museum junior mass reopen famous sing advance salt reform"),
        ("f30f8c1da665478f49b001d94c5fc452",
         "vessel ladder alter error federal sibling chat ability sun glass valve picture"),
        ("c10ec20dc3cd9f652c7fac2f1230f7a3c828389a14392f05",
         "scissors invite lock maple supreme raw rapid void congress muscle digital elegant little brisk hair mango congress clump"),
        ("f585c11aec520db57dd353c69554b21a89b20fb0650966fa0a9d6f74fd989d8f",
         "void come effort suffer camp survey warrior heavy shoot primary clutch crush open amazing screen patrol group space point ten exist slush involve unfold")
    ]

    @Test("entropy bytes map to the BIP39 reference mnemonics", arguments: vectors)
    func referenceVectors(vector: (entropyHex: String, mnemonic: String)) throws {
        let entropy = try #require(Data(hexString: vector.entropyHex))
        #expect(try BIP39.mnemonic(entropy: entropy) == vector.mnemonic)
    }

    @Test("entropy must be 16 to 32 bytes in steps of 4")
    func entropyLength() {
        for count in [0, 15, 17, 33] {
            #expect(throws: BIP39.Error.invalidEntropyLength(count)) { try BIP39.mnemonic(entropy: Data(repeating: 0, count: count)) }
        }
    }
}

@Suite("Signing key exports from the reference C++")
struct ExportTests {
    static let signingCases = fixture.cases.filter { $0.type == "SigningKey" }

    @Test("OpenSSH and OpenPGP exports match the fixture", arguments: signingCases)
    func exports(vector: Vector) throws {
        let key = try SigningKey.derive(seed: vector.seed, recipe: vector.recipe)
        #expect(try OpenSSH.publicKeyLine(key) == vector.openSshPublicKey)
        let recorded = try #require(vector.openSshPemPrivateKey)
        let sshPrivate = try OpenSSH.privateKeyPEM(key, comment: vector.sshComment ?? "")
        #expect(sshPrivate.count == recorded.count)
        #expect(try maskedOpenSshKey(sshPrivate) == maskedOpenSshKey(recorded))
        let pgp = try OpenPGP.secretKeyBlock(key, userId: vector.pgpUserId ?? "", timestamp: vector.pgpTimestamp ?? 0)
        #expect(pgp == vector.openPgpPemFormatSecretKey)
    }
}

/// The binary body of an OpenSSH private key with its two check-int copies zeroed. The private
/// section starts after the magic, the cipher, KDF and KDF options strings, the key count, the
/// public key blob and the section length.
func maskedOpenSshKey(_ pem: String) throws -> [UInt8] {
    let body = pem.split(separator: "\n").filter { !$0.hasPrefix("-----") }.joined()
    var bytes = [UInt8](try #require(Data(base64Encoded: body)))
    var offset = "openssh-key-v1\0".utf8.count
    func uint32(at index: Int) -> Int {
        bytes[index..<index + 4].reduce(0) { $0 << 8 | Int($1) }
    }
    for _ in 0..<3 { offset += 4 + uint32(at: offset) }
    offset += 4
    offset += 4 + uint32(at: offset)
    offset += 4
    for index in offset..<offset + 8 { bytes[index] = 0 }
    return bytes
}

private extension Data {
    init?(hexString: String) {
        let chars = Array(hexString.utf8)
        guard chars.count % 2 == 0 else { return nil }
        var bytes = [UInt8]()
        var index = 0
        while index < chars.count {
            guard let byte = UInt8(String(decoding: chars[index..<index + 2], as: UTF8.self), radix: 16) else { return nil }
            bytes.append(byte)
            index += 2
        }
        self.init(bytes)
    }
}
