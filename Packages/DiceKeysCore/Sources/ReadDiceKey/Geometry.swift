//
//  Geometry.swift
//  ReadDiceKey
//

import simd

/// A point or vector in image pixels, x to the right and y down.
typealias Point = SIMD2<Float>

extension SIMD2 where Scalar == Float {
    /// The unit vector at `angle` radians, measured clockwise on screen from +x.
    init(angle: Float) {
        self.init(cos(angle), sin(angle))
    }

    /// The direction in radians, clockwise on screen from +x, in -pi...pi.
    var angle: Float { atan2(y, x) }

    var length: Float { simd_length(self) }

    /// The vector turned a quarter turn clockwise on screen.
    var turnedClockwise: Self { Self(-y, x) }
}

/// A rotated rectangle in the image; the shape the scanner looks for undoverlines in.
struct Bar: Sendable {
    var center: Point
    /// Unit vector along the long side.
    var axis: Point
    var length: Float
    var width: Float

    var area: Float { length * width }

    /// Whether `point` lies inside the rectangle or on its edge.
    func contains(_ point: Point) -> Bool {
        let offset = point - center
        return abs(simd_dot(offset, axis)) <= length / 2 && abs(simd_dot(offset, axis.turnedClockwise)) <= width / 2
    }
}
