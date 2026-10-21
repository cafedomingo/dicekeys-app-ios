//
//  PaperPreview.swift
//  DiceKeys
//

import PDFKit
import SwiftUI
import UniformTypeIdentifiers

/// The page as it will print, drawn from the same PDF that prints, with Print as the main
/// action and saving a PDF second. A secret page stays concealed until Show, and can't be
/// printed or saved while the screen is shared or recorded.
struct PaperPreview<Page: View>: View {
    let title: String
    let filename: String
    let isSecret: Bool
    @ViewBuilder let page: (_ concealed: Bool) -> Page

    @Environment(\.dismiss) private var dismiss
    @Environment(\.isSceneCaptured) private var isSceneCaptured
    @State private var isShown = false
    @State private var isConfirmingSave = false
    @State private var fileToSave: PDFFile?
    @State private var error: PresentableError?
    @State private var preview: Data?

    private var isBlocked: Bool { isSecret && isSceneCaptured }

    var body: some View {
        NavigationStack {
            PDFPageView(pdf: preview)
                .ignoresSafeArea(edges: .bottom)
                .navigationTitle(title)
                .toolbarTitleDisplayMode(.inline)
                .toolbar { toolbar }
        }
        .concealsWhenExposed($isShown)
        .onChange(of: isSecret && !isShown, initial: true) { _, concealed in
            preview = try? PrintedPage.pdf(of: page(concealed), size: PrintedPage.letter)
        }
        .alert("Save the recovery sheet as a file?", isPresented: $isConfirmingSave) {
            Button("Save as PDF…") { save() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The file is the DiceKey. Anyone who opens it, or any backup it lands in, has every key.")
        }
        .fileExporter(
            isPresented: Binding(get: { fileToSave != nil }, set: { if !$0 { fileToSave = nil } }),
            document: fileToSave, contentType: .pdf, defaultFilename: filename
        ) { result in
            if case .failure(let error) = result { self.error = PresentableError(title: "Couldn't Save", error: error) }
        }
        .errorAlert($error)
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button("Done", systemImage: "xmark") { dismiss() }
        }
        ToolbarItem(placement: .confirmationAction) {
            Button("Print", systemImage: "printer", action: print).disabled(isBlocked)
        }
        ToolbarItemGroup(placement: .secondaryAction) {
            if isSecret {
                Button(isShown ? "Hide" : "Show", systemImage: isShown ? "eye.slash" : "eye") { isShown.toggle() }
                    .disabled(isSceneCaptured)
            }
            Button("Save as PDF…", systemImage: "square.and.arrow.down") {
                if isSecret { isConfirmingSave = true } else { save() }
            }
            .disabled(isBlocked)
        }
    }

    private func print() {
        do {
            let info = UIPrintInfo.printInfo()
            info.jobName = filename
            let controller = UIPrintInteractionController.shared
            controller.printInfo = info
            controller.printingItem = try PrintedPage.pdf(of: page(false), size: PrintedPage.letter)
            controller.present(animated: true) { controller, _, _ in controller.printingItem = nil }
        } catch {
            self.error = PresentableError(title: "Couldn't Print", error: error)
        }
    }

    private func save() {
        do {
            fileToSave = PDFFile(data: try PrintedPage.pdf(of: page(false), size: PrintedPage.letter))
        } catch {
            self.error = PresentableError(title: "Couldn't Save", error: error)
        }
    }
}

private struct PDFPageView: UIViewRepresentable {
    let pdf: Data?

    func makeUIView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.backgroundColor = .clear
        return view
    }

    func updateUIView(_ view: PDFView, context: Context) {
        guard context.coordinator.pdf != pdf else { return }
        context.coordinator.pdf = pdf
        view.document = pdf.flatMap(Self.flattened)
    }

    private static let pixelsPerPoint: CGFloat = 3

    /// The page as pixels: text in the preview could be selected and copied to the clipboard,
    /// which neither stays local nor expires. Print and Save use the PDF itself.
    private static func flattened(_ pdf: Data) -> PDFDocument? {
        guard let page = PDFDocument(data: pdf)?.page(at: 0) else { return nil }
        let size = page.bounds(for: .mediaBox).size
        let image = page.thumbnail(
            of: CGSize(width: size.width * pixelsPerPoint, height: size.height * pixelsPerPoint), for: .mediaBox)
        guard let flat = PDFPage(image: image) else { return nil }
        let document = PDFDocument()
        document.insert(flat, at: 0)
        return document
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    /// The PDF on screen, so an unrelated update doesn't reload it and reset the zoom.
    final class Coordinator {
        var pdf: Data?
    }
}

private struct PDFFile: FileDocument {
    static let readableContentTypes = [UTType.pdf]

    let data: Data

    init(data: Data) {
        self.data = data
    }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else { throw CocoaError(.fileReadCorruptFile) }
        self.data = data
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}
