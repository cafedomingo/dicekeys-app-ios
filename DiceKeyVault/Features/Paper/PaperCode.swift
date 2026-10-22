//
//  PaperCode.swift
//  DiceKeyVault
//

import CoreImage.CIFilterBuiltins
import SwiftUI

/// The 2D codes printed on paper.
enum PaperCode {
    enum Symbology { case qr, aztec }

    /// Medium: paper kept in a box or a safe, not scuffed in a wallet.
    private static let qrCorrectionLevel = "M"
    /// Percent of the symbol spent on error correction; 23 is the generator's default and
    /// the usual minimum.
    private static let aztecCorrectionLevel: Float = 33

    /// The smallest module, in points, a phone camera reads off paper. The list card's QR code
    /// was sized to it; whether the recovery sheet's denser Aztec codes read at it is still to
    /// confirm by printing one with many keys.
    static let minimumModuleSide: CGFloat = 0.9

    /// The widest code, in modules, that draws at `side` points with modules no smaller
    /// than `minimumModuleSide`.
    static func maximumWidth(atSide side: CGFloat) -> Int { Int(side / minimumModuleSide) }

    /// Black modules on white, one pixel per module; nil if the text doesn't fit.
    static func image(for text: String, symbology: Symbology) -> CGImage? {
        let output: CIImage?
        switch symbology {
        case .qr:
            let filter = CIFilter.qrCodeGenerator()
            filter.message = Data(text.utf8)
            filter.correctionLevel = qrCorrectionLevel
            output = filter.outputImage
        case .aztec:
            let filter = CIFilter.aztecCodeGenerator()
            filter.message = Data(text.utf8)
            filter.correctionLevel = aztecCorrectionLevel
            output = filter.outputImage
        }
        guard let output else { return nil }
        return CIContext().createCGImage(output, from: output.extent)
    }
}

/// A code drawn with sharp modules at `side` points, or nothing if it doesn't fit.
struct PaperCodeView: View {
    let image: CGImage
    let side: CGFloat

    var body: some View {
        Image(decorative: image, scale: 1)
            .interpolation(.none)
            .resizable()
            .frame(width: side, height: side)
    }
}
