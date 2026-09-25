//
//  PlatformTypes.swift
//  DiceKeys
//
//  Created by bakhtiyor on 28/12/20.
//

import UIKit

extension UIFont {
    /// The bundled Inconsolata Bold face used on the dice, falling back to the
    /// system monospaced font if the custom font failed to register.
    static func inconsolataBold(size: CGFloat) -> UIFont {
        UIFont(name: "Inconsolata-Bold", size: size) ?? UIFont.monospacedSystemFont(ofSize: size, weight: .bold)
    }
}
