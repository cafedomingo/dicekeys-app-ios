//
//  EditableDiceKeyState.swift
//  DiceKeys
//
//  Created by Stuart Schechter on 2021/01/22.
//

import Observation

/// The 25 partially-entered faces of a DiceKey being typed in by hand.
@MainActor @Observable
final class EditableDiceKeyState {
    var faces: [PartialFace]
    var faceSelectedIndex: Int = 0

    init() {
        faces = (0...24).map { PartialFace(index: $0) }
    }

    var diceKey: DiceKey? {
        let faces = faces.compactMap(\.face)
        guard faces.count == 25 else { return nil }
        return DiceKey(faces)
    }

    var faceSelected: PartialFace {
        get { faces[faceSelectedIndex] }
        set { if faceSelectedIndex >= 0 && faceSelectedIndex < 25 { faces[faceSelectedIndex] = newValue } }
    }

    private var letter: FaceLetter? {
        get { faceSelected.letter }
        set { faceSelected.letter = newValue }
    }

    private var digit: FaceDigit? {
        get { faceSelected.digit }
        set { faceSelected.digit = newValue }
    }

    private var orientation: FaceOrientationLetterTrbl {
        get { faceSelected.orientation }
        set { faceSelected.orientation = newValue }
    }

    func moveNext() {
        faceSelectedIndex = min(24, faceSelectedIndex + 1)
    }

    func movePrev() {
        faceSelectedIndex = max(0, faceSelectedIndex - 1)
    }

    func rotateLeft() {
        faceSelected.orientation = faceSelected.orientation.left
    }

    func rotateRight() {
        faceSelected.orientation = faceSelected.orientation.right
    }

    func enter(letter: FaceLetter) {
        if self.letter != nil && digit != nil && faceSelectedIndex < 24 {
            // This die is complete so we'll assume the user wants to enter the letter
            // for the next die
            moveNext()
        }
        self.letter = letter
    }

    func enter(digit: FaceDigit) {
        if letter != nil && self.digit != nil && faceSelectedIndex < 24 {
            // This die is complete so we'll assume the user wants to enter the digit
            // for the next die
            moveNext()
        }
        self.digit = digit
    }

    func delete() {
        letter = nil
        digit = nil
        orientation = .Top
    }

    func backspace() {
        if faceSelectedIndex > 0 && letter == nil && digit == nil {
            movePrev()
        }
        delete()
    }

    func keyDown(char: Character) {
        if let letterKey = FaceLetter(rawValue: String(char)) {
            enter(letter: letterKey)
        } else if let digitKey = FaceDigit(rawValue: String(char)) {
            enter(digit: digitKey)
        }
    }
}
