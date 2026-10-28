//
//  PaperTests.swift
//  DiceKeyVaultTests
//

import CoreImage
import CryptoKit
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
    private static let file = PaperFormatV2Tests.expected
    private static let readScale: CGFloat = 8
    private static let quietZone: CGFloat = 32

    private static func code() throws -> RecoveryCode {
        try RecoveryCode(payload: Fixture.text("recovery-v2.txt"))
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

    /// A name DEFLATE can't shrink, up to 43 characters: repeated text would fit far more keys in a code.
    private static func incompressibleName(_ index: Int, length: Int) -> String {
        String(Data(SHA256.hash(data: Data("\(index)".utf8))).base64URLEncodedString.prefix(length))
    }

    /// The two defaults, as every list holds them, then `count` named keys.
    private static func manyKeys(_ count: Int, nameLength: Int) throws -> CatalogFile {
        var file = Self.file
        let named = try (0..<count).map { try KeyRecipe(kind: .ssh, name: incompressibleName($0, length: nameLength)) }
        file.keys = (KeyRecipe.defaults + named).map { CatalogFile.KeyItem(diceKey: file.diceKeys[0].id, recipe: $0) }
        return file
    }

    @Test("the list card's QR code is capped at version 25 by the shared module size")
    func listCardCap() {
        #expect(ListCard.maximumWidth == 119)
    }

    @Test("the list card's PDF names every key and never holds the faces")
    func cardHoldsNoSecret() throws {
        let text = try Self.cardText(Self.file)
        for key in Self.file.namedKeys { #expect(text.contains(Self.searchable(key.recipe.title))) }
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
        let text = try Self.cardText(Self.manyKeys(30, nameLength: 43))
        #expect(text.contains("more in the exported file"))
    }

    @Test("the list card's code holds forty keys")
    func cardHoldsFortyKeys() throws {
        let link = try Self.manyKeys(40, nameLength: 12).importURL.absoluteString
        let image = try #require(PaperCode.image(for: link, symbology: .qr))
        #expect(image.width <= ListCard.maximumWidth)
        #expect(try Self.read(image, symbology: .qr) == link)
    }

    @Test("the recovery sheet's code holds eighty keys")
    func sheetHoldsEightyKeys() throws {
        let recipes = try (0..<80).map { try KeyRecipe(kind: .ssh, name: Self.incompressibleName($0, length: 12)) }
        let entries = (KeyRecipe.defaults + recipes).map { KeyEntry(diceKeyID: DiceKey.example.id, recipe: $0) }
        let code = try RecoveryCode(diceKey: .example, record: DiceKeyRecord(diceKey: .example), entries: entries)
        let image = try #require(PaperCode.image(for: code.payload, symbology: RecoverySheet.codeSymbology))
        #expect(image.width <= RecoverySheet.maximumCodeWidth)
    }

    @Test("too many keys for a scannable code says so, and doesn't point at the code")
    func tooManyKeysForTheCode() throws {
        let text = try Self.cardText(Self.manyKeys(300, nameLength: 20))
        #expect(text.contains("Too many keys for the code"))
        #expect(!text.contains("more in the code"))
    }

    /// A recovery sheet for `count` SSH keys, with their public keys as the app has them.
    private static func sheetText(keys count: Int) throws -> String {
        try sheetText(
            recipes: (0..<count).map { try KeyRecipe(kind: .ssh, name: incompressibleName($0, length: 12)) })
    }

    /// A recovery sheet for these keys, with their public keys as the app has them.
    private static func sheetText(recipes: [KeyRecipe]) throws -> String {
        let context = ModelContext(try Catalog.container(syncing: false, inMemory: true))
        try context.recordIfNew(DiceKey.example)
        for recipe in recipes {
            try context.addEntry(
                for: DerivedKey.derive(seed: DiceKey.example.seed, recipe: recipe), diceKeyID: DiceKey.example.id)
        }
        let record = try #require(try context.record(for: DiceKey.example.id))
        let entries = try context.entries(for: DiceKey.example.id)
        let code = try RecoveryCode(diceKey: .example, record: record, entries: entries)
        return try text(of: PrintedPage.pdf(of: RecoverySheet(code: code, entries: entries), size: PrintedPage.letter))
    }

    @Test("the printed lists show the named keys only, so no default prints as SSH · SSH")
    func printedListsShowNamedKeysOnly() throws {
        let card = try Self.cardText(Self.file)
        #expect(!card.contains("SSH · SSH"))
        #expect(!card.contains("age · age"))
        let full = try Self.cardText(Self.manyKeys(ListCard.listedKeys, nameLength: 12))
        #expect(!full.contains("more in"))
        #expect(!(try Self.sheetText(keys: RecoverySheet.listedKeys)).contains("SSH · SSH"))
    }

    @Test("the recovery sheet prints a key's first algorithm's public key, not every one")
    func sheetPrintsTheFirstAlgorithmsPublicKey() throws {
        let backups = try KeyRecipe(kind: .age, name: "backups")
        let text = try Self.sheetText(recipes: [backups])
        let derived = DerivedKey.derive(seed: DiceKey.example.seed, recipe: backups)
        #expect(text.contains(try #require(derived.publicKeys["x25519"])))
        #expect(!text.contains("age1pq1"))
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
        let text = try Self.sheetText(keys: 300)
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
