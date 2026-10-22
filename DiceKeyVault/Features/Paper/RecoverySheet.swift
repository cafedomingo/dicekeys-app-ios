//
//  RecoverySheet.swift
//  DiceKeyVault
//

import SwiftUI

/// One page holding the DiceKey itself and its list: the grid, the faces written out for
/// typing back in, the keys, and the recovery code. Anyone with the page has every key.
struct RecoverySheet: View {
    /// Aztec rather than QR, so the Camera app, which reads QR codes, doesn't offer to search
    /// the faces. The scan screen reads both, so a change here leaves printed sheets readable.
    nonisolated static let codeSymbology = PaperCode.Symbology.aztec
    /// Key lines, each with its public key, that fit on the page with everything else; the
    /// rest are only in the code.
    static let listedKeys = 7

    private static let codeSide: CGFloat = 170
    private static let maximumCodeWidth = PaperCode.maximumWidth(atSide: codeSide)
    private static let dieSize: CGFloat = 28
    private static let spacing: CGFloat = 10
    private static let lineSpacing: CGFloat = 2
    private static let keySpacing: CGFloat = 5
    private static let bandPadding: CGFloat = 8
    private static let bandCorner: CGFloat = 8
    private static let bandLineWidth: CGFloat = 2
    private static let facesSize: CGFloat = 12
    private static let publicKeySize: CGFloat = 7.5
    private static let row = 5

    let code: RecoveryCode
    /// Where the public keys come from: the code carries none.
    let entries: [KeyEntry]
    var concealed = false

    private var diceKey: CatalogFile.DiceKeyItem? { code.catalog.diceKeys.first }

    var body: some View {
        let image = (try? code.payload).flatMap { PaperCode.image(for: $0, symbology: Self.codeSymbology) }
            .flatMap { $0.width <= Self.maximumCodeWidth ? $0 : nil }
        VStack(alignment: .leading, spacing: Self.spacing) {
            Text("This page is the DiceKey. Anyone with it has every key below.")
                .font(.headline)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(Self.bandPadding)
                .overlay {
                    RoundedRectangle(cornerRadius: Self.bandCorner)
                        .strokeBorder(Color.danger, lineWidth: Self.bandLineWidth)
                }
            HStack(spacing: Self.spacing) {
                DiceAvatar(centerFace: diceKey?.centerFace ?? "", size: DieView.Size.header)
                VStack(alignment: .leading) {
                    Text(diceKey?.name ?? "").font(.title2.weight(.semibold))
                    Text("\(AppInfo.name) recovery sheet · \(Date.now, format: .dateTime.day().month().year())")
                        .font(.caption)
                }
            }
            HStack(alignment: .top, spacing: Self.spacing) {
                DiceKeyGrid(
                    faces: code.diceKey.faces.map(PartialFace.init), concealed: concealed, dieSize: Self.dieSize)
                Spacer(minLength: 0)
                codeView(image)
            }
            faces
            Divider()
            keyLines(hasCode: image != nil)
            Text(
                "To restore, scan the code from Scan DiceKey in \(AppInfo.name), or type the faces in with Type it in. Each key comes back from its kind, name and settings."
            )
            .font(.caption)
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(PrintedPage.margin)
    }

    @ViewBuilder
    private func codeView(_ image: CGImage?) -> some View {
        if let image, !concealed {
            PaperCodeView(image: image, side: Self.codeSide)
        } else {
            RoundedRectangle(cornerRadius: Self.bandCorner)
                .fill(Color.dieFace)
                .frame(width: Self.codeSide, height: Self.codeSide)
                .overlay {
                    if image == nil {
                        Text("Too many keys for the code. Keep an exported catalog file as well.")
                            .font(.caption)
                            .multilineTextAlignment(.center)
                            .padding(Self.bandPadding)
                    }
                }
        }
    }

    private var faces: some View {
        VStack(alignment: .leading, spacing: Self.lineSpacing) {
            ForEach(0..<DiceKey.faceCount / Self.row, id: \.self) { row in
                let faces = code.diceKey.faces[row * Self.row..<(row + 1) * Self.row]
                Text(faces.map(\.text).joined(separator: " "))
                    .font(.system(size: Self.facesSize, design: .monospaced))
            }
            .redacted(reason: concealed ? .placeholder : [])
            Text("Each die: letter, digit, then which way its top points: t up, r right, b down, l left.")
                .font(.caption)
        }
    }

    private func keyLines(hasCode: Bool) -> some View {
        let keys = code.catalog.keys
        let shown = keys.count > Self.listedKeys ? Self.listedKeys - 1 : keys.count
        return VStack(alignment: .leading, spacing: Self.keySpacing) {
            ForEach(keys.prefix(shown), id: \.self) { key in
                VStack(alignment: .leading, spacing: Self.lineSpacing) {
                    Text(key.printedLine).font(.footnote.weight(.semibold)).lineLimit(1)
                    if let publicKey = publicKey(for: key) {
                        Text(publicKey).font(.system(size: Self.publicKeySize, design: .monospaced)).lineLimit(1)
                    }
                }
            }
            if shown < keys.count {
                Text("and \(keys.count - shown) more in \(hasCode ? "the code" : "the exported file")")
                    .font(.footnote).italic()
            }
        }
    }

    private func publicKey(for key: CatalogFile.KeyItem) -> String? {
        entries.first { $0.recipe == key.recipe }?.publicKey
    }
}
