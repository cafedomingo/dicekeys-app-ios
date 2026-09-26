//
//  MnemonicsTests.swift
//  DiceKeysTests
//
//  Created by Angelos Veglektsis on 7/12/22.
//

import Testing
@testable import DiceKeys

extension StringProtocol {
    var hexAsByteArray: [UInt8] { .init(hexa) }
    private var hexa: UnfoldSequence<UInt8, Index> {
        sequence(state: startIndex) { startIndex in
            guard startIndex < self.endIndex else { return nil }
            let endIndex = self.index(startIndex, offsetBy: 2, limitedBy: self.endIndex) ?? self.endIndex
            defer { startIndex = endIndex }
            return UInt8(self[startIndex..<endIndex], radix: 16)
        }
    }
}

struct MnemonicsTests {
    @Test func wordlist() {
        #expect(Wordlist.english.count == 2048)
    }

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

    @Test("Entropy bytes map to the BIP39 reference mnemonics", arguments: vectors)
    func bytesToMnemonic(vector: (entropyHex: String, mnemonic: String)) throws {
        let words = try Mnemonic.toMnemonic(vector.entropyHex.hexAsByteArray)
        #expect(words.joined(separator: " ") == vector.mnemonic)
    }
}
