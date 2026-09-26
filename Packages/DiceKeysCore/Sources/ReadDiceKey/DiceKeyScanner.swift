//
//  DiceKeyScanner.swift
//  ReadDiceKey
//
//  Swift face of the DiceKeys scanning algorithm, now implemented natively in this
//  module (a port of lib-read-dicekey; see docs/SCANNER-PORT-NOTES.md). One scanner
//  accumulates evidence across camera frames until it has read all 25 faces with
//  enough confidence.
//

import Foundation

/// Reads a DiceKey out of successive RGBA camera frames.
///
/// Not thread-safe: own it from a single actor or serial queue and feed frames in order.
public final class DiceKeyScanner {
    /// The pipeline state (internal so tests can inspect it).
    var reader = DiceKeyReader()

    public init() {}

    /// Feeds one frame of tightly packed 8-bit RGBA pixels.
    /// - Returns: `true` once a complete DiceKey has been read.
    @discardableResult
    public func process(rgba: Data, width: Int, height: Int) -> Bool {
        precondition(rgba.count >= width * height * 4, "RGBA buffer smaller than width * height * 4")
        guard width > 0, height > 0 else { return false }
        return rgba.withUnsafeBytes { raw in
            reader.processRGBA(raw, width: width, height: height)
        }
    }

    /// JSON describing the faces read so far. See the app's `FaceRead.fromJson` for the schema.
    public var readResultJSON: String {
        reader.jsonDiceKeyRead
    }

    /// `true` when the algorithm has reached its termination condition.
    public var isFinished: Bool {
        reader.isFinished
    }

    /// A translucent RGBA overlay (width * height pixels) showing what has been read.
    public func renderOverlay(width: Int, height: Int) -> Data {
        var buffer = Data(count: max(0, width * height * 4))
        guard width > 0, height > 0 else { return buffer }
        buffer.withUnsafeMutableBytes { raw in
            reader.renderAugmentationOverlay(raw, width: width, height: height)
        }
        return buffer
    }

    /// Draws what has been read on top of `rgba` in place.
    public func augment(rgba: inout Data, width: Int, height: Int) {
        precondition(rgba.count >= width * height * 4, "RGBA buffer smaller than width * height * 4")
        guard width > 0, height > 0 else { return }
        rgba.withUnsafeMutableBytes { raw in
            reader.augmentRGBAImage(raw, width: width, height: height)
        }
    }
}
