//
//  PrintedFont.swift
//  DiceKeySpecification
//

import CoreText
import Foundation

/// The typeface printed on the dice. The app draws dice in it and the scanner reads their text
/// against it.
public enum PrintedFont {
    /// The name to draw it by. Reading it first registers the font for this process, so it can be
    /// drawn by name anywhere, previews included.
    public static let name: String = {
        CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        return postScriptName
    }()

    /// The font file.
    public static let url: URL = {
        guard let url = Bundle.module.url(forResource: postScriptName, withExtension: "otf") else {
            preconditionFailure("\(postScriptName).otf is missing from DiceKeySpecification")
        }
        return url
    }()

    private static let postScriptName = "Inconsolata-Bold"
}
