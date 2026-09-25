//
//  String.swift
//  DiceKeys
//
//  Created by Angelos Veglektsis on 7/20/22.
//

import Foundation
import CoreGraphics
import CoreImage
import CoreImage.CIFilterBuiltins
import UIKit

extension String {
    var isBlank: Bool {
        allSatisfy { $0.isWhitespace }
    }

    func trim() -> String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Renders the string as a QR code (error-correction level H), or nil if
    /// Core Image cannot produce one.
    func toQRCode() -> CGImage? {
        let context = CIContext()
        let ciFilter = CIFilter.qrCodeGenerator()
        ciFilter.message = Data(utf8)
        ciFilter.correctionLevel = "H"
        guard let outputImage = ciFilter.outputImage else { return nil }
        return context.createCGImage(outputImage, from: outputImage.extent)
    }

    /// Copies the string to the system pasteboard.
    @MainActor
    func copyToPasteboard() {
        UIPasteboard.general.string = self
    }
}

extension Optional where Wrapped == String {
    var isBlank: Bool {
        self?.isBlank ?? true
    }
}
