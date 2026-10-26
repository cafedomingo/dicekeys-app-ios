//
//  KeyScreen.swift
//  DiceKeyVault
//

import CoreTransferable
import Derivation
import KeyFormats
import SwiftData
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
    /// An age key's post-quantum recipient, which the catalog doesn't hold: derived once the
    /// DiceKey is unlocked, and kept, since it is public.
    @State private var postQuantumRecipient: String?
    @State private var entryToDelete: KeyEntry?
    @Environment(\.isSceneCaptured) private var isSceneCaptured
    @Environment(SavedDiceKeys.self) private var saved
    @Environment(\.modelContext) private var context

    var body: some View {
        if let recipe = entry.recipe {
            Form {
                Section {
                    KeyHeader(recipe: recipe, made: entry.created)
                }
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())
                switch recipe.kind {
                case .ssh, .wireguard:
                    publicKeySection(entry.publicKey)
                case .age:
                    publicKeySection(entry.publicKey, title: AgeRecipient.x25519Title, note: AgeRecipient.x25519Note)
                    publicKeySection(
                        postQuantumRecipient, title: AgeRecipient.postQuantumTitle, note: AgeRecipient.postQuantumNote,
                        foldedLines: AgeRecipient.postQuantumFoldedLines, offersUnlock: entry.publicKey != nil)
                case .passphrase, .wallet:
                    EmptyView()
                }
                secretSection(recipe)
                if !recipe.isDefault {
                    Section {
                        Button("Delete key", systemImage: "trash", role: .destructive) { entryToDelete = entry }
                            .foregroundStyle(Color.danger)
                    }
                }
            }
            .centeredContent()
            .appBackdrop()
            .navigationTitle(recipe.title)
            .toolbarTitleDisplayMode(.inline)
            .toolbar(removing: .title)
            .confirmsKeyDeletion($entryToDelete, onDelete: onDelete)
            .concealsWhenExposed(isRevealed)
            .onChange(of: diceKey == nil) { _, isLocked in
                if isLocked { revealed = nil }
            }
            .task(id: diceKey?.id) {
                guard recipe.kind == .age, postQuantumRecipient == nil, let diceKey else { return }
                postQuantumRecipient = DerivedKey.derive(seed: diceKey.seed, recipe: recipe).postQuantum?.recipient
            }
        } else {
            ContentUnavailableView(
                "Unknown kind", systemImage: "questionmark.key.filled",
                description: Text("A newer version of the app made this key."))
        }
    }

    /// A public key, or until it is known, a note that it shows once the DiceKey is unlocked,
    /// and Unlock for a DiceKey kept on this device unless an earlier section offers it.
    @ViewBuilder
    private func publicKeySection(
        _ publicKey: String?, title: String = "Public key", note: String? = nil, foldedLines: Int? = nil,
        offersUnlock: Bool = true
    ) -> some View {
        if let publicKey {
            PublicKeySection(publicKey: publicKey, title: title, note: note, foldedLines: foldedLines)
        } else {
            Section {
                Text("Shows once the DiceKey is unlocked.")
                    .foregroundStyle(.secondary)
                if offersUnlock && saved.contains(id: entry.diceKeyID) {
                    UnlockButton(
                        diceKeyID: entry.diceKeyID, name: (try? context.record(for: entry.diceKeyID))?.name ?? "")
                }
            } header: {
                Text(title)
            } footer: {
                if let note { Text(note) }
            }
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
                if let recipient = revealed.publicKey, let postQuantum = revealed.postQuantum {
                    ageIdentity(revealed.secret, recipient: recipient, postQuantum: false, name: recipe.name ?? "")
                    ageIdentity(
                        postQuantum.identity, recipient: postQuantum.recipient, postQuantum: true,
                        name: recipe.name ?? "")
                } else {
                    SecretView(kind: recipe.kind, secret: revealed.secret)
                    SecretActions(
                        kind: recipe.kind, secret: revealed.secret,
                        file: recipe.kind == .ssh ? KeyFile(ssh: revealed) : nil)
                }
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

    /// One of an age key's two identities, labeled as its recipient's section is.
    @ViewBuilder
    private func ageIdentity(_ identity: String, recipient: String, postQuantum: Bool, name: String) -> some View {
        VStack(alignment: .leading, spacing: .space2) {
            Text(postQuantum ? AgeRecipient.postQuantumTitle : AgeRecipient.x25519Title)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            SecretView(kind: .age, secret: identity)
        }
        SecretActions(
            kind: .age, secret: identity,
            file: KeyFile(
                ageIdentity: identity, recipient: recipient, postQuantum: postQuantum, name: name,
                created: entry.created))
    }
}

/// The key's name, kind and date, or for a default its kind, centered over the key like a
/// card's face rather than rows of a table. It stands in for the navigation title, which stays
/// set for VoiceOver and Back.
private struct KeyHeader: View {
    private static let iconSide: CGFloat = 72

    let recipe: KeyRecipe
    let made: Date

    var body: some View {
        VStack(spacing: .space2) {
            Image(systemName: recipe.kind.symbol)
                .font(.largeTitle)
                .foregroundStyle(.tint)
                .frame(width: Self.iconSide, height: Self.iconSide)
                .background(Color.accentSoft, in: .rect(cornerRadius: .radiusMd))
            Text(recipe.title)
                .font(.title.bold())
                .multilineTextAlignment(.center)
            (recipe.isDefault
                ? Text("Default key")
                : Text("\(recipe.kind.title) · Made \(made, format: .dateTime.day().month().year())"))
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }
}

/// What tells an age key's two recipients apart, on the key and while it is made.
enum AgeRecipient {
    static let x25519Title = "X25519"
    static let x25519Note =
        "For any version of age. A file can be encrypted to it alongside SSH and other X25519 recipients."
    static let postQuantumTitle = "ML-KEM-768 + X25519 (post-quantum)"
    static let postQuantumNote =
        "Safe from future quantum computers. Needs age 1.3 or later, and a file encrypted to it can't also be encrypted to X25519 or SSH recipients."
    /// About 1,950 characters, so it opens folded to this many lines.
    static let postQuantumFoldedLines = 4
}

struct PublicKeySection: View {
    let publicKey: String
    var fingerprint: String?
    let title: String
    /// When to use this key, under it in place of a fingerprint.
    var note: String?
    /// For a key too long to read whole: it shows this many lines until Show all. Copy and
    /// Share always take all of it.
    var foldedLines: Int?

    @State private var isUnfolded = false

    var body: some View {
        Section {
            Text(publicKey)
                .font(.footnote.monospaced())
                .wrapsAnywhere()
                .lineLimit(isUnfolded ? nil : foldedLines)
                .textSelection(.enabled)
            if foldedLines != nil {
                Button(
                    isUnfolded ? "Show less" : "Show all \(publicKey.count) characters",
                    systemImage: isUnfolded ? "chevron.up" : "chevron.down"
                ) { isUnfolded.toggle() }
            }
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
            if let note {
                Text(note)
            } else if let fingerprint, fingerprint != publicKey {
                Text(fingerprint).monospaced().wrapsAnywhere()
            }
        }
    }
}

/// Copy and Share for a revealed secret, the same for every kind but a wallet. Copy says
/// when the clipboard clears; Share hands the secret, or the file its tool reads, to whatever
/// is picked in the sheet.
struct SecretActions: View {
    let kind: KeyKind
    let secret: String
    var file: KeyFile?

    @State private var copiedUntil: Date?

    var body: some View {
        if kind.secretLeavesScreen {
            HStack(spacing: .space3) {
                Button {
                    Clipboard.copySecret(secret)
                    copiedUntil = .now.addingTimeInterval(Clipboard.secretLifetime)
                } label: {
                    CopyLabel()
                }
                if let file {
                    ShareLink(item: file, preview: SharePreview(file.filename)) { ShareLabel() }
                } else {
                    ShareLink(item: secret) { ShareLabel() }
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
            "Delete \(entry.wrappedValue?.recipe?.title ?? "")?",
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
                .wrapsAnywhere()
        }
    }
}

extension View {
    /// Breaks a key or secret between any two characters without the hyphens SwiftUI adds
    /// when it breaks a word, which would read as part of the value.
    func wrapsAnywhere() -> some View {
        typesettingLanguage(.init(languageCode: .unavailable))
    }
}

/// An SSH or age identity, as the file its tool reads.
struct KeyFile: Transferable {
    private static let ssh = (name: "id_ed25519", separator: "_", suffix: "")
    private static let age = (name: "age", separator: "-", suffix: ".txt")
    private static let agePostQuantum = (name: "age-pq", separator: "-", suffix: ".txt")
    private static let slugSeparator = "-"
    /// Go's RFC 3339, as `age-keygen` writes its `# created:` line.
    private static let createdFormat = Date.ISO8601FormatStyle(
        timeZoneSeparator: .colon, timeZone: .autoupdatingCurrent)

    let filename: String
    let contents: String

    /// The OpenSSH private key.
    init(ssh key: DerivedKey) {
        filename = Self.filename(Self.ssh, name: key.recipe.name ?? "")
        contents = key.secret
    }

    /// As `age-keygen` writes it: when the key was made, its recipient, then the identity.
    init(ageIdentity identity: String, recipient: String, postQuantum: Bool, name: String, created: Date) {
        filename = Self.filename(postQuantum ? Self.agePostQuantum : Self.age, name: name)
        contents = "# created: \(created.formatted(Self.createdFormat))\n# public key: \(recipient)\n\(identity)\n"
    }

    /// The tool's usual name, then the key's letters and digits with each run of anything
    /// else, emoji included, as one hyphen; just the tool's name if nothing is left.
    private static func filename(_ file: (name: String, separator: String, suffix: String), name: String) -> String {
        let slug = name.unicodeScalars
            .split { !CharacterSet.alphanumerics.contains($0) }
            .map { String(String.UnicodeScalarView($0)) }
            .joined(separator: slugSeparator)
        return file.name + (slug.isEmpty ? "" : file.separator + slug) + file.suffix
    }

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .plainText) { file in Data(file.contents.utf8) }
            .suggestedFileName { $0.filename }
    }
}
