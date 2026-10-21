//
//  ListCard.swift
//  DiceKeys
//

import SwiftUI

/// The card for the box: the DiceKey's name and center die, its keys, and the list link's QR
/// code. It holds no secret: whoever has the box already has every key.
struct ListCard: View {
    /// Millimeters; a guess from photos of the box, to tune once it is measured.
    static let side: CGFloat = 70
    /// Millimeters.
    static let codeSide: CGFloat = 38
    /// The widest QR code, in modules as the generator draws them with its one-module margin:
    /// 119, version 25.
    static let maximumWidth = PaperCode.maximumWidth(atSide: codeSide * PrintedPage.pointsPerMillimeter)
    /// Key lines that fit beside the code before the rest are only in the code.
    static let listedKeys = 8

    private static let padding: CGFloat = 8
    private static let spacing: CGFloat = 6
    private static let lineSpacing: CGFloat = 2
    private static let titleSize: CGFloat = 11
    private static let lineSize: CGFloat = 6.5
    private static let noteSize: CGFloat = 5.5

    let file: CatalogFile

    private var diceKey: CatalogFile.DiceKeyItem? { file.diceKeys.first }
    private var code: CGImage? {
        (try? file.importURL.absoluteString)
            .flatMap { PaperCode.image(for: $0, symbology: .qr) }
            .flatMap { $0.width <= Self.maximumWidth ? $0 : nil }
    }

    var body: some View {
        let side = Self.side * PrintedPage.pointsPerMillimeter
        let code = code
        VStack(alignment: .leading, spacing: Self.spacing) {
            HStack(spacing: Self.spacing) {
                DiceAvatar(centerFace: diceKey?.centerFace ?? "", size: DieView.Size.row)
                Text(diceKey?.name ?? "").font(.system(size: Self.titleSize, weight: .semibold)).lineLimit(2)
            }
            HStack(alignment: .top, spacing: Self.spacing) {
                if let code {
                    PaperCodeView(image: code, side: Self.codeSide * PrintedPage.pointsPerMillimeter)
                }
                keyLines(hasCode: code != nil)
            }
            Spacer(minLength: 0)
            Text(
                code == nil
                    ? "Too many keys for the code. Keep an exported catalog file as well."
                    : "No secret here. Scan in \(AppInfo.name) to restore this list."
            )
            .font(.system(size: Self.noteSize))
        }
        .padding(Self.padding)
        .frame(width: side, height: side, alignment: .topLeading)
    }

    private func keyLines(hasCode: Bool) -> some View {
        let keys = file.keys
        let shown = keys.count > Self.listedKeys ? Self.listedKeys - 1 : keys.count
        return VStack(alignment: .leading, spacing: Self.lineSpacing) {
            ForEach(keys.prefix(shown), id: \.self) { key in
                Text(key.cardLine).lineLimit(3).fixedSize(horizontal: false, vertical: true)
            }
            if shown < keys.count {
                Text("and \(keys.count - shown) more in \(hasCode ? "the code" : "the exported file")").italic()
            }
        }
        .font(.system(size: Self.lineSize))
    }
}

/// A Letter page holding one `ListCard`, with crop marks to cut it out by.
struct ListCardPage: View {
    private static let cropMarkLength: CGFloat = 18
    private static let cropMarkGap: CGFloat = 4
    private static let cropMarkWidth: CGFloat = 0.5

    let file: CatalogFile

    var body: some View {
        let side = ListCard.side * PrintedPage.pointsPerMillimeter
        VStack(spacing: PrintedPage.margin) {
            Text("Cut along the marks and keep the card in the DiceKey's box.").font(.callout)
            ListCard(file: file)
                .background { cropMarks(side: side) }
            Spacer()
        }
        .padding(PrintedPage.margin)
    }

    private func cropMarks(side: CGFloat) -> some View {
        Canvas { context, size in
            var path = Path()
            let gap = Self.cropMarkGap
            let length = Self.cropMarkLength
            for x in [0, size.width] {
                for y in [0, size.height] {
                    let outward: CGFloat = x == 0 ? -1 : 1
                    let downward: CGFloat = y == 0 ? -1 : 1
                    path.move(to: CGPoint(x: x + outward * gap, y: y))
                    path.addLine(to: CGPoint(x: x + outward * (gap + length), y: y))
                    path.move(to: CGPoint(x: x, y: y + downward * gap))
                    path.addLine(to: CGPoint(x: x, y: y + downward * (gap + length)))
                }
            }
            context.stroke(path, with: .foreground, lineWidth: Self.cropMarkWidth)
        }
        .frame(width: side, height: side)
        .allowsHitTesting(false)
    }
}
