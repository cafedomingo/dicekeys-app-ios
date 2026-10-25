//
//  CenteredContent.swift
//  DiceKeyVault
//

import SwiftUI

extension View {
    /// Caps a list's or form's width at `contentWidth`, centered in the column beside any
    /// sidebar. The scroll view is only that wide, so the margins beside it don't scroll.
    /// A content margin instead replaced the floating sidebar's safe-area inset and pushed
    /// the rows off center.
    func centeredContent() -> some View {
        frame(maxWidth: .contentWidth).frame(maxWidth: .infinity)
    }
}
