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
    @Environment(UnlockedDiceKeys.self) private var unlocked
    @Environment(SavedDiceKeys.self) private var saved
    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Query private var records: [DiceKeyRecord]

    var body: some View {
        NavigationSplitView(preferredCompactColumn: $compactColumn) {
            DiceKeyList(
                selection: $sidebarSelection,
                onScan: {
                    sidebarSelection = .scan
                    compactColumn = .detail
                },
                onDelete: delete
            )
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
        .restoresDiceKey($codeToRestore, onRestored: open)
        .errorAlert($error)
    }

    @ViewBuilder
    private var detail: some View {
        switch sidebarSelection {
        case .scan:
            LoadScreen(onLoaded: load, onCodeRead: read)
        case .diceKey(let id):
            if let record = records.uniqueDiceKeys.first(where: { $0.diceKeyID == id }) {
                DiceKeyScreen(
                    record: record, path: $path,
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
            ContentUnavailableView("No DiceKey selected", systemImage: "square.grid.3x3")
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

    private func load(_ diceKey: DiceKey) {
        open(diceKey)
        if !saved.contains(id: diceKey.id) { diceKeyToKeep = diceKey }
    }

    private func open(_ diceKey: DiceKey) {
        do {
            try context.recordIfNew(diceKey)
        } catch {
            self.error = PresentableError(title: "Couldn't Record DiceKey", error: error)
        }
        unlocked.unlock(diceKey)
        sidebarSelection = .diceKey(diceKey.id)
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
        close(id)
        Task {
            if isOpen { try? await Task.sleep(for: Self.backNavigationDuration) }
            close(id)
            do {
                try context.deleteKey(recipe, diceKeyID: diceKeyID)
            } catch {
                self.error = PresentableError(title: "Couldn't Delete", error: error)
            }
        }
    }

    private func close(_ id: PersistentIdentifier) {
        path.removeAll { $0 == .entry(id) }
        if sidebarSelection == .key(id) { sidebarSelection = nil }
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
