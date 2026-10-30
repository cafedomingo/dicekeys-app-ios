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

/// A screen pushed in the detail column: a key or New key over its DiceKey's screen, or the
/// camera over whatever the column shows beside home.
enum KeySelection: Hashable {
    case entry(PersistentIdentifier)
    case new
    case scan
}

/// Home, with every DiceKey and its keys, then whichever of them is selected. One split view
/// for every size: a phone shows the columns as a stack.
struct ContentView: View {
    private static let backNavigationDuration = Duration.milliseconds(400)

    @State private var sidebarSelection: SidebarSelection?
    @State private var path: [KeySelection] = []
    /// Set alongside the selection, since a phone pushes only for a sidebar list's selection
    /// and home before the first DiceKey has no list. The split view sets it back on Back, which
    /// clears the scanner's selection there too.
    @State private var compactColumn = NavigationSplitViewColumn.sidebar
    @State private var error: PresentableError?
    @State private var diceKeyToKeep: DiceKey?
    @State private var catalogToImport: CatalogFile?
    @State private var codeToRestore: RecoveryCode?
    /// The DiceKey a scan or typing just recorded for the first time, while its screen stays open.
    @State private var newDiceKeyID: String?
    /// The scanner's typing, kept here through a resize that moves the scanner between the
    /// selection and a push. Dropped when the scanner closes, and once the app has been in the
    /// background as long as an unlocked DiceKey may be, since half a DiceKey is still most of a
    /// secret.
    @State private var isTyping = false
    @State private var typed = TypedDiceKey()
    @State private var backgroundedAt: Date?
    @Environment(UnlockedDiceKeys.self) private var unlocked
    @Environment(SavedDiceKeys.self) private var saved
    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Query private var records: [DiceKeyRecord]
    /// Every row, since the public keys map can't be filtered in the store.
    @Query private var entries: [KeyEntry]

    var body: some View {
        NavigationSplitView(preferredCompactColumn: $compactColumn) {
            DiceKeyList(selection: $sidebarSelection, onScan: scan, onDelete: delete)
                .appBackdrop(dice: sizeClass == .compact)
        } detail: {
            NavigationStack(path: $path) {
                detail.navigationDestination(for: KeySelection.self, destination: pushed)
            }
        }
        .onChange(of: sidebarSelection, selectionChanged)
        .onChange(of: compactColumn) { _, column in
            if column == .sidebar, sidebarSelection == .scan { sidebarSelection = nil }
        }
        .onChange(of: sizeClass) { _, size in fitScanner(to: size) }
        .onChange(of: isScanning) { _, isScanning in
            if !isScanning {
                isTyping = false
                typed = TypedDiceKey()
            }
        }
        .onChange(of: isDraftLocked) { _, isLocked in
            if isLocked { closeDraft() }
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .background:
                unlocked.appWentToBackground()
                backgroundedAt = backgroundedAt ?? .now
            case .inactive:
                unlocked.appReturned()
            case .active:
                unlocked.appReturned()
                expireTyping()
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
            loadScreen
        case .diceKey(let id):
            if let record = records.uniqueDiceKeys.first(where: { $0.diceKeyID == id }) {
                DiceKeyScreen(
                    record: record, isNew: newDiceKeyID == id, path: $path,
                    onScan: scan,
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
        case .scan:
            loadScreen
        }
    }

    private var loadScreen: some View {
        LoadScreen(
            isCompact: sizeClass == .compact, isTyping: $isTyping, typed: typed, onLoaded: load,
            onCodeRead: read)
    }

    @ViewBuilder
    private func keyScreen(_ id: PersistentIdentifier) -> some View {
        if let entry = context.model(for: id) as? KeyEntry {
            KeyScreen(
                entry: entry, diceKey: unlocked.diceKey(id: entry.diceKeyID), onScan: scan, onDelete: delete
            )
            .id(id)
        }
    }

    /// What the public key fill runs on: keys that need one whose DiceKey is unlocked, rather
    /// than the unlocked DiceKeys, so a key an import or a sync adds to an unlocked DiceKey fills
    /// too.
    private var keysToFill: Set<PersistentIdentifier> {
        entries.keysToFill { unlocked.diceKey(id: $0) != nil }
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

    /// A phone shows the camera in place of home. Beside home it is pushed over the detail column,
    /// so Back returns to whatever that showed.
    private func scan() {
        if sizeClass == .compact {
            sidebarSelection = .scan
            compactColumn = .detail
        } else if sidebarSelection != .scan, path.last != .scan {
            path.append(.scan)
        }
    }

    private var isScanning: Bool {
        sidebarSelection == .scan || path.contains(.scan)
    }

    /// Clears the pushed screens, which belong to the old selection, except when widening has just
    /// moved the camera from the selection to a push.
    private func selectionChanged(from old: SidebarSelection?, to selection: SidebarSelection?) {
        if old != .scan || selection != nil { path = [] }
        compactColumn = selection == nil ? .sidebar : .detail
        if let id = diceKeyID(of: selection) { unlocked.use(id: id) }
        if let newDiceKeyID, selection != .diceKey(newDiceKeyID) { self.newDiceKeyID = nil }
    }

    private func expireTyping() {
        if let backgroundedAt, Date.now.timeIntervalSince(backgroundedAt) >= UnlockedDiceKeys.lockDelay {
            typed = TypedDiceKey()
        }
        backgroundedAt = nil
    }

    /// A phone selects the camera and a wider window pushes it, so a resize moves it to the form
    /// its new width uses.
    private func fitScanner(to size: UserInterfaceSizeClass?) {
        if size == .compact, sidebarSelection == nil, path.last == .scan {
            sidebarSelection = .scan
        } else if size != .compact, sidebarSelection == .scan {
            sidebarSelection = nil
            path = [.scan]
        }
    }

    private func load(_ diceKey: DiceKey) {
        newDiceKeyID = open(diceKey) ? diceKey.id : nil
        if !saved.contains(id: diceKey.id) { diceKeyToKeep = diceKey }
    }

    /// True when this is the first time the DiceKey is recorded. Clears the pushed screens too, since
    /// scanning the DiceKey that is already open leaves the selection as it was.
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
        path = []
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
