//
//  TypedDiceKey.swift
//  DiceKeyVault
//

import DiceKeySpecification
import Observation

/// A DiceKey being typed in by hand: each die's letter, then its digit, then which way is up.
@MainActor @Observable
final class TypedDiceKey {
    enum Step {
        case letter, digit, orientation
    }

    private(set) var faces = Array(repeating: PartialFace(), count: DiceKey.faceCount)
    /// Nil once every die is in, until one is tapped to redo it.
    var selectedIndex: Int? = 0

    var selectedFace: PartialFace? { selectedIndex.map { faces[$0] } }

    /// What the selected die needs next. A complete die starts over at its letter, so tapping
    /// one and typing redoes it.
    var step: Step? {
        guard let face = selectedFace else { return nil }
        if face.letter == nil || face.face != nil { return .letter }
        return face.digit == nil ? .digit : .orientation
    }

    /// Letters on the other dice, which the selected die can't take: each is on one die only.
    var usedLetters: Set<FaceLetter> {
        Set(faces.indices.filter { $0 != selectedIndex }.compactMap { faces[$0].letter })
    }

    /// Tapping the die already selected in a finished DiceKey puts it down again, so a tap to
    /// look doesn't have to become a redo.
    func select(_ index: Int) {
        selectedIndex = index == selectedIndex && diceKey != nil ? nil : index
    }

    /// Nil until every die is in. Its letters are distinct, since a used letter can't be typed.
    var diceKey: DiceKey? {
        let faces = faces.compactMap(\.face)
        return faces.count == DiceKey.faceCount ? DiceKey(faces) : nil
    }

    func enter(letter: FaceLetter) {
        guard let index = selectedIndex, !usedLetters.contains(letter) else { return }
        faces[index] = PartialFace(letter: letter)
    }

    func enter(digit: FaceDigit) {
        guard let index = selectedIndex, step == .digit else { return }
        faces[index].digit = digit
    }

    /// Completes the die and moves on to the next one still to type, or selects none when
    /// every die is in.
    func choose(_ orientation: FaceOrientationLetterTrbl) {
        guard let index = selectedIndex, step == .orientation else { return }
        faces[index].orientation = orientation
        let later = Array(index + 1..<faces.count) + Array(0..<index)
        selectedIndex = later.first { faces[$0].face == nil }
    }

    /// Undoes one step: the selected die's last entry, or, on an empty die, the previous die's
    /// orientation. With none selected, that is the last die's orientation.
    func backspace() {
        guard let selectedIndex else {
            self.selectedIndex = faces.count - 1
            faces[faces.count - 1].orientation = nil
            return
        }
        var face = faces[selectedIndex]
        if face.orientation != nil {
            face.orientation = nil
        } else if face.digit != nil {
            face.digit = nil
        } else if face.letter != nil {
            face.letter = nil
        } else if selectedIndex > 0 {
            self.selectedIndex = selectedIndex - 1
            faces[selectedIndex - 1].orientation = nil
            return
        }
        faces[selectedIndex] = face
    }
}
