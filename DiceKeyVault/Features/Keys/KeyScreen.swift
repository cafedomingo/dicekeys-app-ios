//
//  KeyScreen.swift
//  DiceKeyVault
//

import CoreTransferable
import Derivation
import KeyFormats
import SwiftUI
import UniformTypeIdentifiers

/// One key: public by default. The secret is derived only on a deliberate Reveal, which sits
/// where the secret will show whether or not the DiceKey is unlocked, and dropped on Hide, on
/// lock, and whenever it could be seen by others.
struct KeyScreen: View {
    let entry: KeyEntry
    /// Nil while the DiceKey is locked: the public key still shows, the secret can't.
    let diceKey: DiceKey?
    let onScan: () -> Void
    let onDelete: (KeyEntry) -> Void

    @State private var revealed: DerivedKey?
    @State private var entryToDelete: KeyEntry?
    @Environment(\.isSceneCaptured) private var isSceneCaptured
    @Environment(SavedDiceKeys.self) private var saved
    @Environment(\.modelContext) private var context

    var body: some View {
        if let recipe = entry.recipe {
            Form {
                Section {
                    KeyHeader(name: recipe.name, kind: recipe.kind, made: entry.created)
                }
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())
                if let publicKey = entry.publicKey {
                    PublicKeySection(publicKey: publicKey)
                }
                secretSection(recipe)
                Section {
                    Button("Delete key", systemImage: "trash", role: .destructive) { entryToDelete = entry }
                        .foregroundStyle(Color.danger)
                }
            }
            .appBackdrop()
            .navigationTitle(recipe.name)
            .toolbarTitleDisplayMode(.inline)
            .toolbar(removing: .title)
            .confirmsKeyDeletion($entryToDelete, onDelete: onDelete)
            .concealsWhenExposed(isRevealed)
            .onChange(of: diceKey == nil) { _, isLocked in
                if isLocked { revealed = nil }
            }
        } else {
            ContentUnavailableView(
                "Unknown kind", systemImage: "questionmark.key.filled",
                description: Text("A newer version of the app made this key."))
        }
    }

    private var isRevealed: Binding<Bool> {
        Binding(get: { revealed != nil }, set: { if !$0 { revealed = nil } })
    }

    private func reveal(_ recipe: KeyRecipe, from diceKey: DiceKey) {
        revealed = DerivedKey.derive(seed: diceKey.seed, recipe: recipe)
    }

    @ViewBuilder
    private func secretSection(_ recipe: KeyRecipe) -> some View {
        Section {
            if let revealed {
                SecretView(kind: recipe.kind, secret: revealed.secret)
                SecretActions(key: revealed)
                Button("Hide", systemImage: "eye.slash") { self.revealed = nil }
            } else if let diceKey {
                Button("Reveal", systemImage: "eye") { reveal(recipe, from: diceKey) }
                    .primaryAction()
                    .disabled(isSceneCaptured)
                    .frame(maxWidth: .infinity)
            } else if saved.contains(id: entry.diceKeyID) {
                UnlockButton(
                    diceKeyID: entry.diceKeyID, name: (try? context.record(for: entry.diceKeyID))?.name ?? "",
                    title: "Reveal"
                ) { reveal(recipe, from: $0) }
                .primaryAction()
                .disabled(isSceneCaptured)
                .frame(maxWidth: .infinity)
            } else {
                Button("Scan or type the dice to reveal", systemImage: "camera.viewfinder", action: onScan)
            }
        } header: {
            Text(recipe.kind.secretTitle)
        }
    }
}

/// The key's name, kind and date, centered over the key like a card's face rather than rows of
/// a table. It stands in for the navigation title, which stays set for VoiceOver and Back.
private struct KeyHeader: View {
    private static let iconSide: CGFloat = 72

    let name: String
    let kind: KeyKind
    let made: Date

    var body: some View {
        VStack(spacing: .space2) {
            Image(systemName: kind.symbol)
                .font(.largeTitle)
                .foregroundStyle(.tint)
                .frame(width: Self.iconSide, height: Self.iconSide)
                .background(Color.accentSoft, in: .rect(cornerRadius: .radiusMd))
            Text(name)
                .font(.title.bold())
                .multilineTextAlignment(.center)
            Text("\(kind.title) · Made \(made, format: .dateTime.day().month().year())")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }
}

struct PublicKeySection: View {
    let publicKey: String
    var fingerprint: String?
    var title = "Public key"

    var body: some View {
        Section {
            Text(publicKey)
                .font(.footnote.monospaced())
                .textSelection(.enabled)
            HStack(spacing: .space3) {
                Button {
                    Clipboard.copy(publicKey)
                } label: {
                    CopyLabel()
                }
                ShareLink(item: publicKey) { ShareLabel() }
            }
            .buttonStyle(.bordered)
        } header: {
            Text(title)
        } footer: {
            if let fingerprint, fingerprint != publicKey {
                Text(fingerprint).monospaced()
            }
        }
    }
}

/// Copy and Share for a revealed secret, the same for every kind but a wallet. Copy says
/// when the clipboard clears; Share hands the secret to whatever is picked in the sheet.
struct SecretActions: View {
    let key: DerivedKey

    @State private var copiedUntil: Date?

    var body: some View {
        if key.recipe.kind.secretLeavesScreen {
            HStack(spacing: .space3) {
                Button {
                    Clipboard.copySecret(key.secret)
                    copiedUntil = .now.addingTimeInterval(Clipboard.secretLifetime)
                } label: {
                    CopyLabel()
                }
                if key.recipe.kind.sharesAsFile {
                    let file = KeyFile(key: key)
                    ShareLink(item: file, preview: SharePreview(file.filename)) { ShareLabel() }
                } else {
                    ShareLink(item: key.secret) { ShareLabel() }
                }
            }
            .buttonStyle(.bordered)
            .task(id: copiedUntil) {
                guard let copiedUntil else { return }
                try? await Task.sleep(for: .seconds(copiedUntil.timeIntervalSinceNow))
                if !Task.isCancelled { self.copiedUntil = nil }
            }
            if let copiedUntil {
                Text("Copied to this device only. Clears \(copiedUntil, style: .relative).")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        } else {
            Text("Write these words down. They are never copied or shared.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }
}

/// Copy and Share sit side by side under the value, each taking half the row.
struct CopyLabel: View {
    var body: some View { Label("Copy", systemImage: "doc.on.doc").frame(maxWidth: .infinity) }
}

struct ShareLabel: View {
    var body: some View { Label("Share", systemImage: "square.and.arrow.up").frame(maxWidth: .infinity) }
}

extension View {
    /// Asks before deleting the key set in `entry`, saying how to get it back.
    func confirmsKeyDeletion(_ entry: Binding<KeyEntry?>, onDelete: @escaping (KeyEntry) -> Void) -> some View {
        alert(
            "Delete \(entry.wrappedValue?.recipe?.name ?? "")?",
            isPresented: Binding(get: { entry.wrappedValue != nil }, set: { if !$0 { entry.wrappedValue = nil } }),
            presenting: entry.wrappedValue
        ) { entry in
            Button("Delete key", role: .destructive) { onDelete(entry) }
            Button("Cancel", role: .cancel) {}
        } message: { _ in
            Text("The key stays in the dice. Make it again with the same kind, name and settings to get it back.")
        }
    }
}

/// A revealed secret, written so it can be read off the screen: a recovery phrase as
/// numbered words to write down, anything else whole.
struct SecretView: View {
    private static let wordColumnWidth: CGFloat = 120

    let kind: KeyKind
    let secret: String

    var body: some View {
        if kind == .wallet {
            let words = secret.split(separator: " ")
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: Self.wordColumnWidth), alignment: .leading)],
                spacing: .space2
            ) {
                ForEach(Array(words.enumerated()), id: \.offset) { index, word in
                    Text("\(index + 1). \(word)").font(.body.monospaced())
                }
            }
        } else {
            Text(secret)
                .font(kind == .passphrase ? .title3.monospaced() : .footnote.monospaced())
        }
    }
}

/// An SSH or age identity, as the file its tool reads.
struct KeyFile: Transferable {
    private static let ssh = (name: "id_ed25519", separator: "_", suffix: "")
    private static let age = (name: "age", separator: "-", suffix: ".txt")
    private static let slugSeparator = "-"

    let key: DerivedKey

    /// The tool's usual name, then the key's letters and digits with each run of anything
    /// else, emoji included, as one hyphen; just the tool's name if nothing is left.
    var filename: String {
        let file = key.recipe.kind == .ssh ? Self.ssh : Self.age
        let slug = key.recipe.name.unicodeScalars
            .split { !CharacterSet.alphanumerics.contains($0) }
            .map { String(String.UnicodeScalarView($0)) }
            .joined(separator: Self.slugSeparator)
        return file.name + (slug.isEmpty ? "" : file.separator + slug) + file.suffix
    }

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .plainText) { file in Data(file.key.secret.utf8) }
            .suggestedFileName { $0.filename }
    }
}
