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
import UniformTypeIdentifiers

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

    /// Copies the string to this device's pasteboard for one minute.
    @MainActor
    func copyToPasteboard() {
        UIPasteboard.general.setItems(
            [[UTType.utf8PlainText.identifier: self]],
            options: [.localOnly: true, .expirationDate: Date(timeIntervalSinceNow: 60)]
        )
    }
}
