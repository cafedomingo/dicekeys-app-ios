//
//  DiceKeyScreen.swift
//  DiceKeys
//
//  Created by Stuart Schechter on 2020/11/27.
//

import SwiftUI

/// The screen for a DiceKey that is unlocked in memory. The former hand-drawn
/// footer is now a `TabView`; "Save" lives in the toolbar and opens a sheet.
struct DiceKeyScreen: View {
    private enum Page: Hashable {
        case diceKey
        case secrets
        case backup
    }

    @Environment(AppRouter.self) private var router
    @Environment(DiceKeyMemoryStore.self) private var diceKeyMemoryStore

    @State private var selectedPage: Page = .diceKey
    @State private var showStorageOptions = false
    @State private var backupProgress = BackupProgress()
    @AppStorage(Settings.hideDiceExceptCenterDie) private var hideDiceExceptCenterDie = false

    var body: some View {
        if let diceKeyState = diceKeyMemoryStore.diceKeyState {
            content(diceKeyState: diceKeyState)
        } else {
            // The key expired; RootView pops this screen.
            ProgressView()
        }
    }

    private func content(diceKeyState: UnlockedDiceKeyState) -> some View {
        let diceKey = diceKeyState.diceKey
        return TabView(selection: $selectedPage) {
            Tab("DiceKey", image: "DiceKey Icon", value: Page.diceKey) {
                VStack {
                    Spacer()
                    DiceKeyView(diceKey: diceKey, showLidTab: true, hideFaces: true, withShowDiceLabel: true)
                        .padding(.horizontal, 15)
                    Spacer()
                }
            }
            Tab("Secrets", image: "Secret with Arrow", value: Page.secrets) {
                RecipeListView()
            }
            Tab("Backup", image: "Backup to DiceKey", value: Page.backup) {
                BackupDiceKeyView(
                    diceKey: diceKey,
                    onDiceKeyReplaced: { diceKeyMemoryStore.setDiceKey(diceKey: $0) },
                    onComplete: { selectedPage = .diceKey },
                    progress: backupProgress
                )
            }
        }
        .tabBarMinimizeBehavior(.onScrollDown)
        .ignoresSafeArea(.keyboard)
        .navigationTitle(diceKeyState.nickname)
        .toolbarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    hideDiceExceptCenterDie.toggle()
                } label: {
                    Label(hideDiceExceptCenterDie ? "Show Dice" : "Hide Dice",
                          systemImage: hideDiceExceptCenterDie ? "eye" : "eye.slash")
                }
            }
            ToolbarSpacer(.fixed, placement: .primaryAction)
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showStorageOptions = true
                } label: {
                    Label(diceKeyState.isDiceKeyStored ? "Saved" : "Save",
                          systemImage: diceKeyState.isDiceKeyStored ? "checkmark.circle.fill" : "square.and.arrow.down")
                }
            }
        }
        .sheet(isPresented: $showStorageOptions) {
            SaveDiceKeySheet(diceKeyState: diceKeyState)
                .presentationDetents([.medium, .large])
                .privacyCover()
        }
        .onAppear {
            if router.showStorageOptionsOnPresent {
                router.showStorageOptionsOnPresent = false
                showStorageOptions = true
            }
        }
    }
}

#Preview {
    NavigationStack {
        DiceKeyScreen()
    }
    .appEnvironment(AppModel.preview(diceKey: DiceKey.createFromRandom()))
}
