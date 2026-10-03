//
//  ColoredSecretText.swift
//  DiceKeys
//

import SwiftUI

/// Which tint a character of a displayed secret gets. Emoji are neither letters nor
/// symbols here: an emoji password is all picture, and tinting it would mean nothing.
enum SecretGlyph: Equatable {
    case plain, digit, symbol

    static func classify(_ character: Character) -> SecretGlyph {
        if character.isNumber { return .digit }
        if character.isLetter || character.isWhitespace { return .plain }
        if character.unicodeScalars.first?.properties.isEmojiPresentation == true { return .plain }
        return .symbol
    }
}

/// A derived value with digits and symbols tinted, so 0 and O or 1 and l read apart and
/// the shape of a random password shows. The text itself is untouched.
struct ColoredSecretText: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(attributed)
    }

    /// The text in runs of one glyph class, each tinted once.
    private var attributed: AttributedString {
        var result = AttributedString()
        var run = ""
        var runGlyph = SecretGlyph.plain
        func flush() {
            guard !run.isEmpty else { return }
            var piece = AttributedString(run)
            switch runGlyph {
            case .digit: piece.foregroundColor = Color.Interface.digitText
            case .symbol: piece.foregroundColor = Color.Interface.symbolText
            case .plain: break
            }
            result += piece
            run = ""
        }
        for character in text {
            let glyph = SecretGlyph.classify(character)
            if glyph != runGlyph {
                flush()
                runGlyph = glyph
            }
            run.append(character)
        }
        flush()
        return result
    }
}

#Preview {
    VStack {
        ColoredSecretText("abide7ACORN3acts")
        ColoredSecretText("sbBhvg8mP*q2_bcP")
        ColoredSecretText("🐶🍎🚀⛵🎸🔑")
    }
    .font(.body.monospaced())
}
