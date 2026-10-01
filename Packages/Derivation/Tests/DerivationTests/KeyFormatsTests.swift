//
//  KeyFormatsTests.swift
//  DerivationTests
//

import Derivation
import Foundation
import Testing

@testable import KeyFormats

@Suite("BIP39")
struct BIP39Tests {
    static let vectors: [(entropyHex: String, mnemonic: String)] = [
        (
            "00000000000000000000000000000000",
            "abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about"
        ),
        (
            "7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f",
            "legal winner thank year wave sausage worth useful legal winner thank yellow"
        ),
        (
            "066dca1a2bb7e8a1db2832148ce9933eea0f3ac9548d793112d9a95c9407efad",
            "all hour make first leader extend hole alien behind guard gospel lava path output census museum junior mass reopen famous sing advance salt reform"
        ),
        (
            "f30f8c1da665478f49b001d94c5fc452",
            "vessel ladder alter error federal sibling chat ability sun glass valve picture"
        ),
        (
            "c10ec20dc3cd9f652c7fac2f1230f7a3c828389a14392f05",
            "scissors invite lock maple supreme raw rapid void congress muscle digital elegant little brisk hair mango congress clump"
        ),
        (
            "f585c11aec520db57dd353c69554b21a89b20fb0650966fa0a9d6f74fd989d8f",
            "void come effort suffer camp survey warrior heavy shoot primary clutch crush open amazing screen patrol group space point ten exist slush involve unfold"
        )
    ]

    @Test("entropy bytes map to the BIP39 reference mnemonics", arguments: vectors)
    func referenceVectors(vector: (entropyHex: String, mnemonic: String)) throws {
        let entropy = try #require(Data(hexString: vector.entropyHex))
        #expect(try BIP39.mnemonic(entropy: entropy) == vector.mnemonic)
    }

    @Test("the English list has 2048 words")
    func wordlistSize() {
        #expect(Wordlist.english.count == 2048)
    }

    @Test("entropy must be 16 to 32 bytes in steps of 4")
    func entropyLength() {
        for count in [0, 15, 17, 33] {
            #expect(throws: BIP39.Error.invalidEntropyLength(count)) {
                try BIP39.mnemonic(entropy: Data(repeating: 0, count: count))
            }
        }
    }
}

extension Data {
    fileprivate init?(hexString: String) {
        let chars = Array(hexString.utf8)
        guard chars.count % 2 == 0 else { return nil }
        var bytes = [UInt8]()
        var index = 0
        while index < chars.count {
            guard let byte = UInt8(String(decoding: chars[index..<index + 2], as: UTF8.self), radix: 16) else {
                return nil
            }
            bytes.append(byte)
            index += 2
        }
        self.init(bytes)
    }
}
