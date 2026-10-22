//
//  DiceKeyScreen.swift
//  DiceKeyVault
//

import Derivation
import SwiftData
import SwiftUI

/// A DiceKey and its keys. The keys show whether or not it is unlocked; the grid, making a
/// key and revealing one need it unlocked.
struct DiceKeyScreen: View {
    let record: DiceKeyRecord
    @Binding var path: [KeySelection]
    let onScan: () -> Void
    let onForget: () -> Void
    let onDelete: (KeyEntry) -> Void

    @Environment(UnlockedDiceKeys.self) private var unlocked
    @Environment(SavedDiceKeys.self) private var saved
    @Environment(\.modelContext) private var context
    @Environment(\.isSceneCaptured) private var isSceneCaptured
    @Query private var entries: [KeyEntry]
    @State private var isGridShown = false
    @State private var isRenaming = false
    @State private var isConfirmingForget = false
    @State private var keyToDelete: KeyEntry?
    @State private var isShowingListCard = false
    @State private var isShowingRecoverySheet = false
    @State private var error: PresentableError?

    init(
        record: DiceKeyRecord, path: Binding<[KeySelection]>, onScan: @escaping () -> Void,
        onForget: @escaping () -> Void, onDelete: @escaping (KeyEntry) -> Void
    ) {
        self.record = record
        _path = path
        self.onScan = onScan
        self.onForget = onForget
        self.onDelete = onDelete
        let diceKeyID = record.diceKeyID
        _entries = Query(filter: #Predicate<KeyEntry> { $0.diceKeyID == diceKeyID }, animation: .default)
    }

    private var diceKey: DiceKey? { unlocked.diceKey(id: record.diceKeyID) }

    var body: some View {
        let keys = entries.uniqueKeys
        List {
            Section {
                DiceKeyHeader(record: record, keyCount: keys.count, isUnlocked: diceKey != nil)
                if let diceKey {
                    DiceKeyGrid(diceKey: diceKey, concealed: !isGridShown)
                        .frame(maxWidth: .infinity)
                        .onTapGesture { if !isSceneCaptured { isGridShown.toggle() } }
                    Button(isGridShown ? "Hide dice" : "Show dice", systemImage: isGridShown ? "eye.slash" : "eye") {
                        isGridShown.toggle()
                    }
                    .disabled(isSceneCaptured)
                } else {
                    lockedActions
                }
            }
            Section("Keys") {
                ForEach(keys) { entry in
                    NavigationLink(value: KeySelection.entry(entry.persistentModelID)) { KeyRow(entry: entry) }
                        .swipeActions(allowsFullSwipe: false) {
                            Button("Delete", systemImage: "trash") { keyToDelete = entry }
                                .tint(Color.danger)
                        }
                }
            }
        }
        .listStyle(.insetGrouped)
        .appBackdrop()
        .navigationTitle(record.name)
        .toolbarTitleDisplayMode(.inline)
        .toolbar { toolbar }
        .concealsWhenExposed($isGridShown)
        .task(id: diceKey?.id) {
            if let diceKey { try? context.fillPublicKeys(for: diceKey) }
        }
        .alert("Rename DiceKey", isPresented: $isRenaming) {
            RenameField(record: record)
        }
        .confirmationDialog("Forget \(record.name)?", isPresented: $isConfirmingForget) {
            Button("Forget DiceKey and its keys", role: .destructive, action: onForget)
        } message: {
            Text("The keys can be made again from the dice, if you remember their names.")
        }
        .confirmsKeyDeletion($keyToDelete, onDelete: onDelete)
        .sheet(isPresented: $isShowingListCard) {
            PaperPreview(title: "List card", filename: "\(record.name) list card", isSecret: false) { _ in
                ListCardPage(file: CatalogFile(records: [record], entries: entries))
            }
        }
        .sheet(isPresented: $isShowingRecoverySheet) {
            if let diceKey {
                PaperPreview(title: "Recovery sheet", filename: "\(record.name) recovery sheet", isSecret: true) {
                    RecoverySheet(
                        code: RecoveryCode(diceKey: diceKey, record: record, entries: entries), entries: keys,
                        concealed: $0)
                }
            }
        }
        .onChange(of: diceKey == nil) { _, isLocked in
            if isLocked { isShowingRecoverySheet = false }
        }
        .errorAlert($error)
    }

    /// Asks for Face ID or the passcode again first: the sheet is the DiceKey itself.
    private func makeRecoverySheet() {
        Task {
            do {
                _ = try await DeviceOwner.authenticate(reason: "Make a recovery sheet for \(record.name)")
                isShowingRecoverySheet = true
            } catch  where !error.isAuthenticationCancellation {
                self.error = PresentableError(title: "Couldn't Make the Recovery Sheet", error: error)
            } catch {}
        }
    }

    @ViewBuilder
    private var lockedActions: some View {
        let isSaved = saved.contains(id: record.diceKeyID)
        Text(
            isSaved
                ? "Locked. Unlock to see the dice and make or reveal keys."
                : "Locked, and not kept on this device, so read the dice again. Once it is unlocked, Keep on this device lets Face ID unlock it."
        )
        .font(.subheadline)
        .foregroundStyle(.secondary)
        if isSaved {
            UnlockButton(diceKeyID: record.diceKeyID, name: record.name)
        } else {
            Button("Scan or type the dice", systemImage: "camera.viewfinder", action: onScan)
        }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Button("New key", systemImage: "plus") { path.append(.new) }
                .disabled(diceKey == nil)
        }
        ToolbarItemGroup(placement: .secondaryAction) {
            if let diceKey {
                Toggle("Keep on this device", systemImage: "faceid", isOn: keepsOnDevice(diceKey))
                Button("Lock", systemImage: "lock") { unlocked.lock(id: record.diceKeyID) }
            }
            Button("List card", systemImage: "printer") { isShowingListCard = true }
            if diceKey != nil {
                Button("Recovery sheet", systemImage: "exclamationmark.lock", action: makeRecoverySheet)
            }
            Button("Rename", systemImage: "pencil") { isRenaming = true }
            Button("Forget", systemImage: "trash", role: .destructive) { isConfirmingForget = true }
        }
    }

    private func keepsOnDevice(_ diceKey: DiceKey) -> Binding<Bool> {
        Binding(
            get: { saved.contains(id: diceKey.id) },
            set: { keep in
                do {
                    if keep { try saved.save(diceKey) } else { try saved.delete(id: diceKey.id) }
                } catch {
                    self.error = PresentableError(title: "Keychain Unavailable", error: error)
                }
            })
    }
}

struct DiceKeyHeader: View {
    private static let spacing: CGFloat = 12
    private static let lineSpacing: CGFloat = 2

    let record: DiceKeyRecord
    let keyCount: Int
    let isUnlocked: Bool

    var body: some View {
        HStack(spacing: Self.spacing) {
            DiceAvatar(centerFace: record.centerFace, size: DieView.Size.header)
            VStack(alignment: .leading, spacing: Self.lineSpacing) {
                Text(record.name).font(.title2.weight(.semibold))
                Text(status).font(.footnote).foregroundStyle(.secondary)
            }
        }
    }

    private var status: AttributedString {
        let keys =
            keyCount == 0
            ? AttributedString("New DiceKey · no keys yet")
            : AttributedString(localized: "^[\(keyCount) key](inflect: true)")
        return keys + AttributedString(isUnlocked ? " · unlocked" : " · locked")
    }
}

struct KeyRow: View {
    private static let iconSide: CGFloat = 36

    let entry: KeyEntry

    var body: some View {
        if let recipe = entry.recipe {
            Label {
                Text(recipe.name).font(.headline)
                Text(recipe.kind.title)
            } icon: {
                Image(systemName: recipe.kind.symbol)
                    .foregroundStyle(.tint)
                    .frame(width: Self.iconSide, height: Self.iconSide)
                    .background(Color.accentSoft, in: .rect(cornerRadius: .radiusSm))
            }
        }
    }
}

/// Edits a copy and saves on Done; clearing the field brings back the name from the center die.
private struct RenameField: View {
    let record: DiceKeyRecord
    @State private var name: String
    @Environment(\.modelContext) private var context

    init(record: DiceKeyRecord) {
        self.record = record
        _name = State(initialValue: record.name)
    }

    var body: some View {
        TextField(record.defaultName, text: $name)
        Button("Cancel", role: .cancel) {}
        Button("Done") {
            let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
            record.name = trimmed.isEmpty ? record.defaultName : trimmed
            try? context.save()
        }
    }
}
