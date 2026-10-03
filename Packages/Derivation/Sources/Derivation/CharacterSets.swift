//
//  CharacterSets.swift
//  Derivation
//

/// Single-character lists for random passwords and PINs.
enum CharacterSets {
    private static let upper = "ABCDEFGHJKLMNPQRSTUVWXYZ"  // no I or O
    private static let lower = "abcdefghijkmnopqrstuvwxyz"  // no l
    private static let digits = "23456789"  // no 0 or 1
    private static let symbols = "!@#$%&*-_?"

    static let lettersDigitsSymbols = characters(upper + lower + digits + symbols)
    static let lettersDigits = characters(upper + lower + digits)
    static let lettersSymbols = characters(upper + lower + symbols)
    static let letters = characters(upper + lower)
    /// A PIN keeps every digit; look-alikes only matter next to letters.
    static let pinDigits = characters("0123456789")

    private static func characters(_ text: String) -> [String] {
        text.map(String.init)
    }
}
