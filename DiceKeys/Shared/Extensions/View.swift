//
//  View.swift
//  DiceKeys
//
//  Created by Stuart Schechter on 2020/11/25.
//

import SwiftUI

extension View {
    /// Applies `content` to the view only when `conditional` is true.
    @ViewBuilder
    func `if`<Content: View>(_ conditional: Bool, @ViewBuilder content: (Self) -> Content) -> some View {
        if conditional {
            content(self)
        } else {
            self
        }
    }

    /// Hides the view (keeping its layout space) when `hidden` is true.
    @ViewBuilder
    func hideIf(_ hidden: Bool) -> some View {
        if hidden {
            self.hidden()
        } else {
            self
        }
    }

    /// Hides the view (keeping its layout space) unless `show` is true.
    @ViewBuilder
    func showIf(_ show: Bool) -> some View {
        if show {
            self
        } else {
            self.hidden()
        }
    }
}
