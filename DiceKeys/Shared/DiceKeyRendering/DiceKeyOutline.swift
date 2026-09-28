//
//  DiceKeyOutline.swift
//  DiceKeys
//

import SwiftUI

/// The box and its lid tab as a single outline. A physical DiceKey is a navy object, and on
/// a dark background navy has almost no contrast (about 1.05:1 against the system's dark
/// gray), so dark mode keeps its color and draws a faint edge around it. The two shapes are
/// unioned so the edge has no seam where the tab meets the box.
enum DiceKeyOutline {
    static func path(box: CGRect, cornerRadius: CGFloat, tabRadius: CGFloat?) -> Path {
        let outline = Path(roundedRect: box, cornerRadius: cornerRadius)
        guard let tabRadius else { return outline }
        var tab = Path()
        tab.addArc(center: CGPoint(x: box.midX, y: box.maxY), radius: tabRadius,
                   startAngle: .degrees(0), endAngle: .degrees(180), clockwise: false)
        tab.closeSubpath()
        return outline.union(tab)
    }

    /// A hairline on thumbnails, growing with the box so it stays visible on a full-width one.
    static func edgeWidth(forBoxSize size: CGFloat) -> CGFloat {
        max(1, size / 200)
    }
}
