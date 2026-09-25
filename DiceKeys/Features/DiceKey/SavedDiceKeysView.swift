//
//  SavedDiceKeysView.swift
//  DiceKeys
//
//  Created by Stuart Schechter on 2021/02/18.
//

import SwiftUI

/// One DiceKey that is unlocked in memory, with its expiration menu.
private struct DiceKeyInMemory: View {
    @Environment(DiceKeyMemoryStore.self) private var diceKeyMemoryStore
    let diceKey: DiceKey
    let saveCallback: ((_ diceKey: DiceKey) -> Void)?
    let onDiceKeySelected: (DiceKey) -> Void

    private var isInEncryptedDataStore: Bool {
        diceKeyMemoryStore.isStoredInKeychain(diceKey)
    }

    private var isCountdownRunning: Bool {
        diceKeyMemoryStore.isCountdownTimerRunning
    }

    private var expirationActionText: String {
        isInEncryptedDataStore ? "Lock" : "Erase"
    }

    private var extensionActionText: String {
        isCountdownRunning ? "Add" : "\(expirationActionText) in"
    }

    private var menuText: String {
        if case .keysNeverExpire = diceKeyMemoryStore.memoryStoreExpirationState {
            return "\(isInEncryptedDataStore ? "Unlocked" : "Will not be erased") until the app is closed"
        } else if isCountdownRunning {
            return "\(isInEncryptedDataStore ? "Locking" : "Erasing") in \(diceKeyMemoryStore.formattedTimeRemaining)"
        } else {
            return ""
        }
    }

    var body: some View {
        VStack(alignment: .center, spacing: 0) {
            Button {
                onDiceKeySelected(diceKey)
            } label: {
                VStack {
                    DiceKeyView(diceKey: diceKey, hideFaces: true)
                        .frame(maxWidth: .infinity)
                    Text(diceKey.nickname).font(.title2)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            Menu {
                if let saveCallback, !isInEncryptedDataStore {
                    Button("Save this DiceKey") { saveCallback(diceKey) }
                    Divider()
                }
                if isCountdownRunning {
                    Button("\(extensionActionText) five minutes") { diceKeyMemoryStore.extendDeadlineBy(seconds: 5 * 60) }
                    Button("\(extensionActionText) one hour") { diceKeyMemoryStore.extendDeadlineBy(seconds: 60 * 60) }
                    Button("Keep keys in memory until I quit") { diceKeyMemoryStore.setKeysNeverExpire() }
                    Divider()
                }
                Button("\(expirationActionText) Immediately", role: .destructive) { diceKeyMemoryStore.expireKey(diceKey) }
            } label: {
                HStack {
                    Text(menuText)
                    Image(systemName: "ellipsis.circle")
                }
            }
            .padding(.vertical, 10)
        }
    }
}

/// One DiceKey that is saved in the keychain but not yet unlocked.
private struct DiceKeyInKeychain: View {
    @Environment(DiceKeyMemoryStore.self) private var diceKeyMemoryStore
    let metadata: StoredEncryptedDiceKeyMetadata
    let onDiceKeyLoaded: (DiceKey) -> Void

    @State private var isUnlocking = false
    @State private var unlockError: PresentableError?

    private var isAlreadyInMemory: Bool {
        !diceKeyMemoryStore.isEmpty && diceKeyMemoryStore.contains(metadata.keyId)
    }

    var body: some View {
        Button {
            unlock()
        } label: {
            VStack {
                if let centerFace = metadata.centerFace {
                    DiceKeyCenterFaceOnlyView(centerFace: centerFace)
                        .frame(maxWidth: .infinity)
                }
                Text((isAlreadyInMemory ? "Open " : "Unlock ") + metadata.nickname).font(.title2)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isUnlocking)
        .errorAlert($unlockError)
    }

    private func unlock() {
        guard !isUnlocking else { return }
        isUnlocking = true
        let metadata = metadata
        Task {
            defer { isUnlocking = false }
            do {
                let diceKey = try await diceKeyMemoryStore.unlock(metadata)
                onDiceKeyLoaded(diceKey)
            } catch {
                if !error.isAuthenticationCancellation {
                    unlockError = PresentableError(title: "Couldn't Unlock DiceKey", error: error)
                }
            }
        }
    }
}

/// The list of DiceKeys unlocked in memory or saved in the keychain, with the
/// ability to open or unlock them.
struct SavedDiceKeysView: View {
    @Environment(DiceKeyMemoryStore.self) private var diceKeyMemoryStore
    @Environment(KnownDiceKeysStore.self) private var knownDiceKeysStore

    let onDiceKeyLoaded: (DiceKey) -> Void
    var saveCallback: ((_ diceKey: DiceKey) -> Void)? = nil

    private var diceKeysStoredInMemory: [DiceKey] { diceKeyMemoryStore.allDiceKeys }

    private var metadataForDiceKeysOnlyStoredEncrypted: [StoredEncryptedDiceKeyMetadata] {
        let idsInMemory = Set(diceKeysStoredInMemory.map(\.id))
        // Do not include keys already loaded into memory
        return knownDiceKeysStore.storedDiceKeys.filter { !idsInMemory.contains($0.keyId) }
    }

    var body: some View {
        VStack(spacing: 24) {
            ForEach(diceKeysStoredInMemory) { diceKey in
                DiceKeyInMemory(
                    diceKey: diceKey,
                    saveCallback: saveCallback,
                    onDiceKeySelected: onDiceKeyLoaded
                )
                .containerRelativeFrame(.vertical) { length, _ in length / 5 }
            }
            ForEach(metadataForDiceKeysOnlyStoredEncrypted) { metadata in
                DiceKeyInKeychain(metadata: metadata, onDiceKeyLoaded: onDiceKeyLoaded)
                    .containerRelativeFrame(.vertical) { length, _ in length / 5 }
            }
        }
    }
}

#Preview {
    ScrollView {
        SavedDiceKeysView(onDiceKeyLoaded: { _ in })
    }
    .appEnvironment(AppModel.preview())
}
