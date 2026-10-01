//
//  ScannedDiceKeyTests.swift
//  DiceKeysTests
//

import DiceKeySpecification
import ReadDiceKey
import Testing

@testable import DiceKeys

@Suite("DiceKey from scanned faces")
struct ScannedDiceKeyTests {
    @Test("letters, digits and quarter turns become faces")
    func mapsFaces() {
        let scanned = FaceLetter.allCases.enumerated().map { i, letter in
            ScannedFace(letter: letter, digit: FaceDigit.allCases[i % 6], clockwiseTurns: i % 4)
        }
        let diceKey = DiceKey(scanned)
        #expect(
            diceKey.faces.map(\.humanReadableForm).joined()
                == scanned.map { face in
                    "\(face.letter.rawValue)\(face.digit.rawValue)\(Array("trbl")[face.clockwiseTurns])"
                }.joined())
    }
}
