//
//  ContentView.swift
//  DiceKeyVault
//

import SwiftData
import SwiftUI

/// What home has selected, which the detail column shows.
enum SidebarSelection: Hashable {
    case scan
    case diceKey(String)
    case key(PersistentIdentifier)
    case newKey(String)
}

/// A screen pushed over a DiceKey's screen in the detail column.
enum KeySelection: Hashable {
    case entry(PersistentIdentifier)
    case new
}

/// Home, with every DiceKey and its keys, then whichever of them is selected. One split view
/// for every size: a phone shows the columns as a stack.
struct ContentView: View {
    private static let backNavigationDuration = Duration.milliseconds(400)

    @State private var sidebarSelection: SidebarSelection?
    @State private var path: [KeySelection] = []
    /// Set alongside the selection, since a phone pushes only for a sidebar list's selection
    /// and home before the first DiceKey has no list. The split view sets it back on Back.
    @State private var compactColumn = NavigationSplitViewColumn.sidebar
    @State private var error: PresentableError?
    @State private var diceKeyToKeep: DiceKey?
    @State private var catalogToImport: CatalogFile?
    @State private var codeToRestore: RecoveryCode?
    /// The DiceKey a scan or typing just recorded for the first time, while its screen stays open.
    @State private var newDiceKeyID: String?
    @Environment(UnlockedDiceKeys.self) private var unlocked
    @Environment(SavedDiceKeys.self) private var saved
    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Query private var records: [DiceKeyRecord]
    @Query(filter: #Predicate<KeyEntry> { $0.publicKey == nil }) private var keysWithoutPublicKeys: [KeyEntry]

    var body: some View {
        NavigationSplitView(preferredCompactColumn: $compactColumn) {
            DiceKeyList(selection: $sidebarSelection, onScan: scan, onDelete: delete)
                .appBackdrop(dice: sizeClass == .compact)
        } detail: {
            NavigationStack(path: $path) {
                detail.navigationDestination(for: KeySelection.self, destination: pushed)
            }
        }
        .onChange(of: sidebarSelection) { _, selection in
            path = []
            compactColumn = selection == nil ? .sidebar : .detail
            if let id = diceKeyID(of: selection) { unlocked.use(id: id) }
            if let newDiceKeyID, selection != .diceKey(newDiceKeyID) { self.newDiceKeyID = nil }
        }
        .onChange(of: isDraftLocked) { _, isLocked in
            if isLocked { closeDraft() }
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .background: unlocked.appWentToBackground()
            case .inactive, .active: unlocked.appReturned()
            @unknown default: break
            }
        }
        .offersToKeep($diceKeyToKeep)
        .onOpenURL { url in
            do {
                catalogToImport = try CatalogFile(importURL: url)
            } catch {
                self.error = PresentableError(title: "Not a Catalog", error: error)
            }
        }
        .importsCatalog($catalogToImport)
        .restoresDiceKey($codeToRestore, onRestored: { open($0) })
        .task(id: records.count) {
            do {
                try context.addMissingDefaults()
            } catch {
                self.error = PresentableError(title: "Couldn't Add Default Keys", error: error)
            }
        }
        .task(id: keysToFill) {
            do {
                for diceKey in unlocked.diceKeys.values { try context.fillPublicKeys(for: diceKey) }
            } catch {
                self.error = PresentableError(title: "Couldn't Save Public Keys", error: error)
            }
        }
        .errorAlert($error)
    }

    @ViewBuilder
    private var detail: some View {
        switch sidebarSelection {
        case .scan:
            LoadScreen(isCompact: sizeClass == .compact, onLoaded: load, onCodeRead: read)
        case .diceKey(let id):
            if let record = records.uniqueDiceKeys.first(where: { $0.diceKeyID == id }) {
                DiceKeyScreen(
                    record: record, isNew: newDiceKeyID == id, path: $path,
                    onScan: { sidebarSelection = .scan },
                    onForget: { forget(record) }, onDelete: delete
                )
                .id(id)
            }
        case .key(let id):
            keyScreen(id)
        case .newKey(let id):
            if let diceKey = unlocked.diceKey(id: id) {
                NewKeyScreen(diceKey: diceKey) { sidebarSelection = .key($0.persistentModelID) }
                    .id(id)
            }
        case nil:
            ContentUnavailableView {
                Label("No DiceKey selected", systemImage: "square.grid.3x3")
            } description: {
                Text(
                    records.isEmpty
                        ? "Scan its 25 dice, or type them in with the keyboard button on the next screen."
                        : "Choose one from the list.")
            } actions: {
                if records.isEmpty {
                    Button("Scan your DiceKey", systemImage: "camera.viewfinder", action: scan).buttonStyle(.bordered)
                }
            }
            .appBackdrop()
        }
    }

    @ViewBuilder
    private func pushed(_ screen: KeySelection) -> some View {
        switch screen {
        case .new:
            if let diceKey = diceKeyID(of: sidebarSelection).flatMap(unlocked.diceKey(id:)) {
                NewKeyScreen(diceKey: diceKey) { path = [.entry($0.persistentModelID)] }
            }
        case .entry(let id):
            keyScreen(id)
        }
    }

    @ViewBuilder
    private func keyScreen(_ id: PersistentIdentifier) -> some View {
        if let entry = context.model(for: id) as? KeyEntry {
            KeyScreen(
                entry: entry, diceKey: unlocked.diceKey(id: entry.diceKeyID), onScan: { sidebarSelection = .scan },
                onDelete: delete
            )
            .id(id)
        }
    }

    /// What the public key fill runs on: keys that need one whose DiceKey is unlocked, rather
    /// than the unlocked DiceKeys, so a key an import or a sync adds to an unlocked DiceKey fills
    /// too.
    private var keysToFill: Set<PersistentIdentifier> {
        Set(
            keysWithoutPublicKeys.filter { unlocked.diceKey(id: $0.diceKeyID) != nil && $0.needsPublicKey }
                .map(\.persistentModelID))
    }

    /// New key is open but its DiceKey has locked, so it has nothing to derive from.
    private var isDraftLocked: Bool {
        guard let id = diceKeyID(of: sidebarSelection), unlocked.diceKey(id: id) == nil else { return false }
        return path.contains(.new) || sidebarSelection == .newKey(id)
    }

    private func closeDraft() {
        path.removeAll { $0 == .new }
        if case .newKey(let id) = sidebarSelection { sidebarSelection = .diceKey(id) }
    }

    /// The DiceKey whose screen is open, if any.
    private func diceKeyID(of selection: SidebarSelection?) -> String? {
        switch selection {
        case .diceKey(let id), .newKey(let id): id
        case .key(let id): (context.model(for: id) as? KeyEntry)?.diceKeyID
        case .scan, nil: nil
        }
    }

    private func scan() {
        sidebarSelection = .scan
        compactColumn = .detail
    }

    private func load(_ diceKey: DiceKey) {
        newDiceKeyID = open(diceKey) ? diceKey.id : nil
        if !saved.contains(id: diceKey.id) { diceKeyToKeep = diceKey }
    }

    /// True when this is the first time the DiceKey is recorded.
    @discardableResult
    private func open(_ diceKey: DiceKey) -> Bool {
        var isNew = false
        do {
            isNew = try context.recordIfNew(diceKey)
        } catch {
            self.error = PresentableError(title: "Couldn't Record DiceKey", error: error)
        }
        unlocked.unlock(diceKey)
        sidebarSelection = .diceKey(diceKey.id)
        return isNew
    }

    private func read(_ payload: String) {
        do {
            switch try ScannedCode(payload: payload) {
            case .list(let file): catalogToImport = file
            case .recovery(let code): codeToRestore = code
            case nil: break
            }
        } catch {
            self.error = PresentableError(title: "Can't Read This Code", error: error)
        }
    }

    /// From the key's own screen, goes back first so the key is seen leaving the list.
    private func delete(_ entry: KeyEntry) {
        guard let recipe = entry.recipe else { return }
        let id = entry.persistentModelID
        let diceKeyID = entry.diceKeyID
        let isOpen = path.contains(.entry(id)) || sidebarSelection == .key(id)
        close(id, returningTo: diceKeyID)
        Task {
            if isOpen { try? await Task.sleep(for: Self.backNavigationDuration) }
            close(id, returningTo: diceKeyID)
            do {
                try context.deleteKey(recipe, diceKeyID: diceKeyID)
            } catch {
                self.error = PresentableError(title: "Couldn't Delete", error: error)
            }
        }
    }

    /// A key opened from the sidebar goes back to its DiceKey where the detail stays beside the
    /// list, as one pushed from the DiceKey's screen does; in a compact window, back to the list.
    private func close(_ id: PersistentIdentifier, returningTo diceKeyID: String) {
        path.removeAll { $0 == .entry(id) }
        if sidebarSelection == .key(id) { sidebarSelection = sizeClass == .compact ? nil : .diceKey(diceKeyID) }
    }

    /// Stops before touching the catalog if the device copy can't be removed, so a DiceKey
    /// is never left in the keychain with nothing in the app pointing at it.
    private func forget(_ record: DiceKeyRecord) {
        do {
            try saved.delete(id: record.diceKeyID)
            unlocked.lock(id: record.diceKeyID)
            sidebarSelection = nil
            try context.forget(record)
        } catch {
            self.error = PresentableError(title: "Couldn't Forget", error: error)
        }
    }
}
