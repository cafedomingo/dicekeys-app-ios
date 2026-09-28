//
//  ScannedDiceKeyTests.swift
//  DiceKeysTests
//

import ReadDiceKey
import Testing
@testable import DiceKeys

@Suite("DiceKey from scanned faces")
struct ScannedDiceKeyTests {
    @Test("letters, digits and quarter turns become faces")
    func mapsFaces() throws {
        let scanned = (0..<25).map { i in
            ScannedFace(letter: Array("ABCDEFGHIJKLMNOPRSTUVWXYZ")[i], digit: Character(String(i % 6 + 1)), clockwiseTurns: i % 4)
        }
        let diceKey = try DiceKey(scanned)
        #expect(diceKey.faces.map(\.humanReadableForm).joined() == scanned.map { face in
            "\(face.letter)\(face.digit)\(Array("trbl")[face.clockwiseTurns])"
        }.joined())
    }
}
