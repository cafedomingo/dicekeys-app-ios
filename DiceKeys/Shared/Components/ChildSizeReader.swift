//
//  ChildSizeReader.swift
//  DiceKeys
//
//  Created by Stuart Schechter on 2020/12/05.
//

import SwiftUI

/// Fills the available space and reports that space through `bounds`.
///
/// Both readers observe their own geometry with `onGeometryChange` rather than a
/// preference key: a preference also collects the values of readers nested inside, and
/// whichever one the key kept won. TransferSticker, which nests the two sticker sheets'
/// readers inside its own, drew its transfer line from a sheet's size instead of its own.
struct CalculateBounds<Content: View>: View {
    @Binding var bounds: CGSize
    let contentBuilder: () -> Content

    init(bounds: Binding<CGSize>, @ViewBuilder contentBuilder: @escaping () -> Content) {
        self._bounds = bounds
        self.contentBuilder = contentBuilder
    }

    var body: some View {
        GeometryReader { _ in
            contentBuilder()
        }
        .onGeometryChange(for: CGSize.self, of: \.size) { bounds = $0 }
    }
}

/// Reports the natural size of its content through `size`.
struct ChildSizeReader<Content: View>: View {
    @Binding var size: CGSize
    let content: () -> Content

    var body: some View {
        content()
            .onGeometryChange(for: CGSize.self, of: \.size) { size = $0 }
    }
}

#Preview {
    struct BoundsTest: View {
        @State private var bounds: CGSize = .zero

        var body: some View {
            CalculateBounds(bounds: $bounds) {
                Text("Hello world \(bounds.height)").frame(maxHeight: bounds.height)
            }
        }
    }
    return BoundsTest()
}
