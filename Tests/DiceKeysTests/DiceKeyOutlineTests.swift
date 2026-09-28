//
//  DiceKeyOutlineTests.swift
//  DiceKeysTests
//

import SwiftUI
import Testing
@testable import DiceKeys

struct DiceKeyOutlineTests {
    @Test("the outline includes the lid tab below the box when there is one")
    func tabExtendsTheOutline() {
        let box = CGRect(x: 0, y: 0, width: 100, height: 100)
        let withTab = DiceKeyOutline.path(box: box, cornerRadius: 10, tabRadius: 12).boundingRect
        let withoutTab = DiceKeyOutline.path(box: box, cornerRadius: 10, tabRadius: nil).boundingRect
        #expect(abs(withTab.maxY - 112) < 0.01)
        #expect(abs(withoutTab.maxY - 100) < 0.01)
        #expect(abs(withTab.width - 100) < 0.01)
    }

    @Test("the edge is a hairline on thumbnails and grows with the box")
    func edgeWidthScales() {
        #expect(DiceKeyOutline.edgeWidth(forBoxSize: 45) == 1)
        #expect(DiceKeyOutline.edgeWidth(forBoxSize: 400) == 2)
    }
}
