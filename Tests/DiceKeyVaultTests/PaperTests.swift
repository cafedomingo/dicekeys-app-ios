//
//  PaperTests.swift
//  DiceKeyVaultTests
//

import CoreImage
import Derivation
import Foundation
import KeyFormats
import PDFKit
import SwiftData
import Testing
import Vision

@testable import DiceKeyVault

@MainActor
struct PaperTests {
    private static let file = CatalogFormatV1Tests.expected
    private static let readScale: CGFloat = 8
    private static let quietZone: CGFloat = 32

    private static func code() throws -> RecoveryCode {
        try RecoveryCode(payload: Fixture.text("recovery-v1.txt"))
    }

    /// Compatibility-mapped, since PDF text extraction returns some CJK characters as their
    /// radical forms, and on one line, since it breaks lines where the page wraps them.
    private static func text(of pdf: Data) throws -> String {
        try #require(PDFDocument(data: pdf)?.string).precomposedStringWithCompatibilityMapping
            .replacingOccurrences(of: "\n", with: " ")
    }

    private static func cardText(_ file: CatalogFile) throws -> String {
        try text(of: PrintedPage.pdf(of: ListCardPage(file: file), size: PrintedPage.letter))
    }

    private static func sheetPDF(concealed: Bool = false) throws -> Data {
        let sheet = RecoverySheet(code: try code(), entries: [], concealed: concealed)
        return try PrintedPage.pdf(of: sheet, size: PrintedPage.letter)
    }

    /// Vision's barcode model doesn't load in the simulator; CIDetector reads QR codes there.
    nonisolated private static let visionUnavailable: Bool = {
        #if targetEnvironment(simulator)
            true
        #else
            false
        #endif
    }()

    /// What a scanner reads from a code image, scaled up and given a quiet zone as on paper.
    private static func read(_ image: CGImage?, symbology: PaperCode.Symbology) throws -> String? {
        let image = CIImage(cgImage: try #require(image))
            .transformed(by: CGAffineTransform(scaleX: readScale, y: readScale))
        let padded = image.composited(
            over: CIImage.white.cropped(to: image.extent.insetBy(dx: -quietZone, dy: -quietZone)))
        if symbology == .qr {
            let detector = CIDetector(ofType: CIDetectorTypeQRCode, context: nil, options: nil)
            return (detector?.features(in: padded).first as? CIQRCodeFeature)?.messageString
        }
        let cgImage = try #require(CIContext().createCGImage(padded, from: padded.extent))
        let request = VNDetectBarcodesRequest()
        request.symbologies = [.aztec]
        try VNImageRequestHandler(cgImage: cgImage).perform([request])
        return request.results?.first?.payloadStringValue
    }

    /// Emoji are drawn as images in a PDF, so its text has only the rest of a name.
    private static func searchable(_ name: String) -> String {
        String(name.unicodeScalars.filter { !$0.properties.isEmojiPresentation }.map(Character.init))
            .trimmingCharacters(in: .whitespaces)
    }

    private static func manyKeys(_ count: Int, nameLength: Int) throws -> CatalogFile {
        var file = Self.file
        file.keys = try (0..<count).map { index in
            let name = String(repeating: "k", count: nameLength - String(index).count) + String(index)
            return CatalogFile.KeyItem(diceKey: file.diceKeys[0].id, recipe: try KeyRecipe(kind: .ssh, name: name))
        }
        return file
    }

    @Test("the list card's QR code is capped at version 25 by the shared module size")
    func listCardCap() {
        #expect(ListCard.maximumWidth == 119)
    }

    @Test("the list card's PDF names every key and never holds the faces")
    func cardHoldsNoSecret() throws {
        let text = try Self.cardText(Self.file)
        for key in Self.file.keys { #expect(text.contains(Self.searchable(key.recipe.name))) }
        let faces = DiceKey.example.faces
        #expect(!text.contains(faces[0].text + " " + faces[1].text))
        #expect(!text.contains(faces[0].text + faces[1].text))
    }

    @Test("the list card's code reads back as the list link")
    func cardCodeReadsBack() throws {
        let link = try Self.file.importURL.absoluteString
        #expect(try Self.read(PaperCode.image(for: link, symbology: .qr), symbology: .qr) == link)
    }

    @Test(
        "the recovery sheet's code reads back as the recovery payload",
        .disabled(if: visionUnavailable && RecoverySheet.codeSymbology == .aztec, "Vision needs a device"))
    func sheetCodeReadsBack() throws {
        let payload = try Self.code().payload
        let symbology = RecoverySheet.codeSymbology
        #expect(try Self.read(PaperCode.image(for: payload, symbology: symbology), symbology: symbology) == payload)
    }

    @Test("the recovery sheet is one page with the warning and the faces written out")
    func sheet() throws {
        let pdf = try Self.sheetPDF()
        #expect(PDFDocument(data: pdf)?.pageCount == 1)
        let text = try Self.text(of: pdf)
        #expect(text.contains("This page is the DiceKey"))
        let firstRow = DiceKey.example.faces.prefix(5).map(\.text).joined(separator: " ")
        #expect(text.contains(firstRow))
    }

    @Test("a concealed recovery sheet holds none of the faces")
    func concealedSheet() throws {
        let text = try Self.text(of: Self.sheetPDF(concealed: true))
        let firstRow = DiceKey.example.faces.prefix(5).map(\.text).joined(separator: " ")
        #expect(text.contains("This page is the DiceKey"))
        #expect(!text.contains(firstRow))
    }

    @Test("a crowded card lists what fits and says how many are left out")
    func crowdedCardSaysWhatIsLeftOut() throws {
        let text = try Self.cardText(Self.manyKeys(30, nameLength: 64))
        #expect(text.contains("more in the exported file"))
    }

    @Test("too many keys for a scannable code says so, and doesn't point at the code")
    func tooManyKeysForTheCode() throws {
        let text = try Self.cardText(Self.manyKeys(300, nameLength: 20))
        #expect(text.contains("Too many keys for the code"))
        #expect(!text.contains("more in the code"))
    }

    /// A recovery sheet for `count` SSH keys, with their public keys as the app has them.
    private static func sheetText(keys count: Int) throws -> String {
        let context = ModelContext(try Catalog.container(syncing: false, inMemory: true))
        try context.recordIfNew(DiceKey.example)
        for index in 0..<count {
            let recipe = try KeyRecipe(kind: .ssh, name: "server \(index)")
            try context.addEntry(
                for: DerivedKey.derive(seed: DiceKey.example.seed, recipe: recipe), diceKeyID: DiceKey.example.id)
        }
        let record = try #require(try context.record(for: DiceKey.example.id))
        let entries = try context.entries(for: DiceKey.example.id)
        let code = RecoveryCode(diceKey: .example, record: record, entries: entries)
        return try text(of: PrintedPage.pdf(of: RecoverySheet(code: code, entries: entries), size: PrintedPage.letter))
    }

    @Test("a recovery sheet with many keys and their public keys keeps its warning and instructions on the page")
    func crowdedSheetStaysOnThePage() throws {
        for count in [RecoverySheet.listedKeys, 14] {
            let text = try Self.sheetText(keys: count)
            #expect(text.contains("This page is the DiceKey"))
            #expect(text.contains("To restore"))
            #expect(text.contains("more in the code") == (count > RecoverySheet.listedKeys))
        }
    }

    @Test("a recovery sheet with too many keys for its code says so, instead of a blank code")
    func sheetTooManyKeysForTheCode() throws {
        let text = try Self.sheetText(keys: 40)
        #expect(text.contains("Too many keys for the code"))
        #expect(!text.contains("more in the code"))
    }

    @Test("names with emoji, quotes and other scripts render on both pages")
    func specialNames() throws {
        var file = Self.file
        file.keys.append(
            CatalogFile.KeyItem(
                diceKey: file.diceKeys[0].id, recipe: try KeyRecipe(kind: .ssh, name: #"quote " and \ مفتاح"#)))
        let text = try Self.cardText(file)
        #expect(text.contains("日本語"))
        #expect(text.contains(#"quote " and"#))
        #expect(try Self.sheetPDF().starts(with: Data("%PDF".utf8)))
    }
}
