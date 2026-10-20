//
//  DiceKey.swift
//  DiceKeys
//

import Derivation
import DiceKeySpecification
import Foundation
import Synchronization

/// 25 dice in reading order. Immutable, so it can cross actors.
final class DiceKey: Equatable, Sendable {
    static let faceCount = 25
    static let centerIndex = 12
    /// After a clockwise quarter turn of the box, position `i` holds the die that was at
    /// `quarterTurnSources[i]`.
    private static let quarterTurnSources = [
        20, 15, 10, 5, 0,
        21, 16, 11, 6, 1,
        22, 17, 12, 7, 2,
        23, 18, 13, 8, 3,
        24, 19, 14, 9, 4
    ]
    /// The reference's recipe, so every DiceKeys app agrees on a DiceKey's id.
    private static let idRecipe = "{\"purpose\":\"a unique identifier for this DiceKey\",\"lengthInBytes\":16}"

    let faces: [Face]
    /// Filled on first use: the id costs a derivation and views read it often.
    private let idCache = Mutex<String?>(nil)

    init(_ faces: [Face]) {
        precondition(faces.count == Self.faceCount)
        self.faces = faces
    }

    /// Parses the 75-character form the keychain stores.
    convenience init(humanReadableForm text: String) throws(DiceKeyFormatError) {
        let characters = Array(text)
        guard characters.count == Self.faceCount * 3 else { throw .wrongLength(characters.count) }
        var faces: [Face] = []
        for start in stride(from: 0, to: characters.count, by: 3) {
            faces.append(try Face(humanReadableForm: String(characters[start..<start + 3])))
        }
        self.init(faces)
    }

    static func == (lhs: DiceKey, rhs: DiceKey) -> Bool { lhs.faces == rhs.faces }

    /// The example key from the reference: letters A to Z without Q, digits 1 to 6, turns
    /// in order.
    static let example = DiceKey(
        (0..<faceCount).map { index in
            Face(
                letter: FaceLetters[index], digit: FaceDigits[index % FaceDigits.count],
                orientation: FaceOrientationLettersTrbl[index % FaceOrientationLettersTrbl.count])
        })

    var centerFace: Face { faces[Self.centerIndex] }

    /// "DiceKey with M1 in center": what a DiceKey is called until it is renamed.
    var defaultName: String { Self.defaultName(centerFace: centerFace.humanReadableForm) }

    /// From the center face's human-readable form, whose first two characters are its letter
    /// and digit.
    static func defaultName(centerFace: String) -> String { "DiceKey with \(centerFace.prefix(2)) in center" }

    /// A real DiceKey has every letter once; anything else is a misread or a typo.

    var humanReadableForm: String { faces.map(\.humanReadableForm).joined() }

    func turnedClockwise() -> DiceKey {
        DiceKey(Self.quarterTurnSources.map { faces[$0].turnedClockwise })
    }

    /// The human-readable form of whichever of the four turns sorts first, so every way of
    /// holding the box derives the same keys.
    var seed: String {
        var turned = self
        var smallest = humanReadableForm
        for _ in 1..<4 {
            turned = turned.turnedClockwise()
            smallest = min(smallest, turned.humanReadableForm)
        }
        return smallest
    }

    /// The reference's 16-byte id, as unpadded URL-safe base64. One-way: it reveals nothing
    /// about the dice.
    var id: String {
        idCache.withLock { cached in
            if let cached { return cached }
            let id = Self.base64URL(idBytes)
            cached = id
            return id
        }
    }

    var idBytes: Data {
        do {
            return try Secret.derive(seed: seed, recipe: Self.idRecipe).bytes
        } catch {
            preconditionFailure("The id recipe failed to derive: \(error)")
        }
    }

    private static func base64URL(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "=", with: "")
    }
}
