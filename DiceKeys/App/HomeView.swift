//
//  HomeView.swift
//  DiceKeys
//

import SwiftUI

/// The home screen: DiceKeys in memory or saved in the keychain, plus the
/// entry points for loading and assembling a DiceKey.
struct HomeView: View {
    @Environment(AppRouter.self) private var router
    @Environment(DiceKeyMemoryStore.self) private var diceKeyMemoryStore
    @Environment(KnownDiceKeysStore.self) private var knownDiceKeysStore

    var body: some View {
        ScrollView {
            VStack(spacing: 32) {
                SavedDiceKeysView(
                    onDiceKeyLoaded: { diceKey in
                        diceKeyMemoryStore.setDiceKey(diceKey: diceKey)
                        router.presentDiceKey()
                    },
                    saveCallback: { diceKey in
                        diceKeyMemoryStore.setDiceKey(diceKey: diceKey)
                        router.presentDiceKey(showStorageOptions: true)
                    }
                )

                Button {
                    router.push(.loadDiceKey)
                } label: {
                    VStack(alignment: .center) {
                        Image("Scanning a DiceKey PNG")
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                        Text("Load your DiceKey").font(.title2)
                    }
                    .aspectRatio(3.0, contentMode: .fit)
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                Button {
                    router.push(.assemblyInstructions)
                } label: {
                    VStack(alignment: .center) {
                        HStack {
                            Image("Illustration of shaking bag").resizable().aspectRatio(contentMode: .fit)
                            Spacer(minLength: 10)
                            Image("Box Bottom After Roll").resizable().aspectRatio(contentMode: .fit)
                            Spacer(minLength: 10)
                            Image("Seal Box").resizable().aspectRatio(contentMode: .fit)
                        }
                        .aspectRatio(4, contentMode: .fit)
                        Text("Assemble \(knownDiceKeysStore.storedDiceKeys.isEmpty ? "your First" : "a") DiceKey").font(.title2)
                    }
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .padding()
            .frame(maxWidth: 700)
            .frame(maxWidth: .infinity)
        }
        .scrollEdgeEffectStyle(.soft, for: .top)
        .navigationTitle("DiceKeys")
    }
}

#Preview {
    NavigationStack {
        HomeView()
    }
    .appEnvironment(AppModel.preview())
}
