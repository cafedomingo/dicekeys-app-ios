//
//  Backdrop.swift
//  DiceKeyVault
//

import SwiftUI

extension View {
    /// The app's ground behind lists and forms: `bg`, washed with `bg-tint` at the top,
    /// so grouped content reads as raised cards rather than sitting on flat white.
    func appBackdrop() -> some View {
        scrollContentBackground(.hidden)
            .background {
                LinearGradient(
                    colors: [Color.bgTint, Color.bg], startPoint: .top,
                    endPoint: .center
                )
                .ignoresSafeArea()
            }
    }
}
