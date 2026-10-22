//
//  PrintedPage.swift
//  DiceKeyVault
//

import Derivation
import SwiftUI

enum PrintedPage {
    /// US Letter in points; it prints on A4 with slightly wider margins.
    static let letter = CGSize(width: 612, height: 792)
    static let margin: CGFloat = 48
    static let pointsPerMillimeter: CGFloat = 72 / 25.4

    /// One PDF page of `view` at `size`, always in light appearance. Anything taller than the
    /// page is cut at the bottom, never the top, where the pages put what matters most.
    @MainActor
    static func pdf(of view: some View, size: CGSize) throws -> Data {
        let renderer = ImageRenderer(
            content: view.frame(width: size.width, height: size.height, alignment: .top)
                .background(.background)
                .environment(\.colorScheme, .light))
        let data = NSMutableData()
        var box = CGRect(origin: .zero, size: size)
        guard let consumer = CGDataConsumer(data: data),
            let context = CGContext(consumer: consumer, mediaBox: &box, nil)
        else { throw CocoaError(.fileWriteUnknown) }
        renderer.render { _, draw in
            context.beginPDFPage(nil)
            draw(context)
            context.endPDFPage()
        }
        context.closePDF()
        return data as Data
    }
}

extension CatalogFile.KeyItem {
    /// "Passphrase · nas · Random, 24 characters", as the paper lists it.
    var printedLine: String {
        ([recipe.kind.title, recipe.name] + [recipe.style?.summary].compactMap(\.self)).joined(separator: " · ")
    }
}

extension CatalogFile.KeyItem {
    /// "nas · Passphrase, 24 characters": the name first, short enough for the card.
    var cardLine: String {
        "\(recipe.name) · \(recipe.kind.title)" + (recipe.style.map { ", " + $0.shortSummary } ?? "")
    }
}

extension PassphraseStyle {
    var shortSummary: String {
        switch self {
        case .random(let length, let symbols): "\(length) characters\(symbols ? " + symbols" : "")"
        case .memorable(let words, let digitsAndUppercase):
            "\(words) words\(digitsAndUppercase ? " + digits, uppercase" : "")"
        }
    }

    /// The settings in words, as the paper prints them.
    var summary: String {
        switch self {
        case .random(let length, let symbols): "Random, \(length) characters\(symbols ? " with symbols" : "")"
        case .memorable(let words, let digitsAndUppercase):
            "Memorable, \(words) words\(digitsAndUppercase ? " with digits and an uppercase word" : "")"
        }
    }
}
