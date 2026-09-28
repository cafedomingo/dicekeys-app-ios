//
//  DiceKeyScanner.swift
//  ReadDiceKey
//
//  Reads a DiceKey from successive camera frames. A face is read only when its underline
//  and overline name the same face, and faces read in different frames are merged until
//  all 25 are known. See docs/SCANNING.md.
//

import CoreGraphics
import DiceKeySpecification

/// One face of a DiceKey.
public struct ScannedFace: Sendable, Hashable {
    public let letter: FaceLetter
    public let digit: FaceDigit
    /// Quarter turns clockwise from upright, 0 to 3, relative to the top of the key.
    public let clockwiseTurns: Int

    public init(letter: FaceLetter, digit: FaceDigit, clockwiseTurns: Int) {
        self.letter = letter
        self.digit = digit
        self.clockwiseTurns = clockwiseTurns
    }
}

/// Where a die of the key lies in the latest frame.
public struct DieInFrame: Sendable {
    /// The middle of the face, in frame pixels.
    public let center: CGPoint
    /// The direction the face reads in (letter to digit), in radians clockwise from the frame's x axis.
    public let angle: Double
    /// The length of the face's edge in frame pixels.
    public let size: Double
    /// The face, once it has been read in this frame or an earlier one.
    public let face: ScannedFace?

    public init(center: CGPoint, angle: Double, size: Double, face: ScannedFace?) {
        self.center = center
        self.angle = angle
        self.size = size
        self.face = face
    }
}

/// Reads a DiceKey out of successive frames. Feed it frames in order from one place.
public struct DiceKeyScanner: Sendable {
    /// The faces read so far, in the reading order of the grid of the last frame they were
    /// lined up with.
    private(set) var faces = [ScannedFace?](repeating: nil, count: 25)

    public init() {}

    /// All 25 faces, rows top to bottom, once every one has been read.
    public var diceKey: [ScannedFace]? {
        let read = faces.compactMap { $0 }
        // A DiceKey has one die per letter. Faces that repeat a letter are something else,
        // such as a sheet of StickKeys stickers, however well they read.
        guard read.count == 25, Set(read.map(\.letter)).count == 25 else { return nil }
        return read
    }

    /// Reads one frame and merges what it shows with the frames before.
    /// - Returns: The dice found in this frame; empty when no key is in view.
    @discardableResult
    public mutating func scan(_ image: GrayImage) -> [DieInFrame] {
        guard let (slots, grid) = readSlots(in: image) else { return [] }
        let gridAngle = grid.across.angle
        let read: [ScannedFace?] = slots.map { slot in
            guard let face = slot.face, let angle = slot.angle else { return nil }
            let turns = Int(((angle - gridAngle) / (.pi / 2)).rounded())
            return ScannedFace(
                letter: face.letter,
                digit: face.digit,
                clockwiseTurns: (turns % 4 + 4) % 4
            )
        }
        let merged = merge(known: faces, read: read)
        if let merged {
            faces = merged
        }
        // Faces that could not be lined up with this frame belong to other positions in it.
        let shown = merged ?? read
        return slots.indices.compactMap { index in
            let slot = slots[index]
            guard let center = slot.center, let angle = slot.angle, let size = slot.size else { return nil }
            return DieInFrame(
                center: CGPoint(x: CGFloat(center.x), y: CGFloat(center.y)),
                angle: Double(angle),
                size: Double(size),
                face: shown[index]
            )
        }
    }
}

/// The faces known after a frame, in its grid's order, or nil when the frame cannot be
/// lined up with the faces already known, which then stand.
///
/// The grid is fitted afresh in every frame, so the key may have turned a quarter turn (or
/// its grid been read that way) since the known faces were read: they are tried in all four
/// turns, and the turn that agrees with this frame on the most faces and disagrees on none
/// is kept. When every turn disagrees somewhere, the camera is on a different key and reading
/// starts over. Five faces in common are needed to call it the same key, because two keys can
/// share a face or two by chance. With fewer, whichever read has more faces stands, so one key
/// is not mixed into another on a coincidence. Successive frames of a key in view read most of
/// its faces, so they share far more than five.
func merge(known: [ScannedFace?], read: [ScannedFace?]) -> [ScannedFace?]? {
    let knownCount = known.compactMap { $0 }.count
    guard knownCount > 0 else { return read }
    var best: (turned: [ScannedFace?], agreements: Int)?
    var turned = known
    for _ in 0..<4 {
        let pairs = zip(turned, read).compactMap { a, b in a.flatMap { a in b.map { (a, $0) } } }
        if pairs.allSatisfy({ $0.0 == $0.1 }), pairs.count > best?.agreements ?? -1 {
            best = (turned, pairs.count)
        }
        turned = turnedClockwise(turned)
    }
    guard let best else { return read }
    guard best.agreements >= 5 else {
        return read.compactMap { $0 }.count > knownCount ? read : nil
    }
    return zip(best.turned, read).map { $1 ?? $0 }
}

/// The faces as they read after the whole key turns a quarter turn clockwise: the die in
/// row r, column c moves to row c, column 4 - r, and turns with the key.
private func turnedClockwise(_ faces: [ScannedFace?]) -> [ScannedFace?] {
    var turned = faces
    for row in 0..<5 {
        for column in 0..<5 {
            turned[column * 5 + (4 - row)] = faces[row * 5 + column].map {
                ScannedFace(letter: $0.letter, digit: $0.digit, clockwiseTurns: ($0.clockwiseTurns + 1) % 4)
            }
        }
    }
    return turned
}
