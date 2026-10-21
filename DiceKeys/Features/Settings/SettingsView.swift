//
//  SettingsView.swift
//  DiceKeys
//

import SwiftUI

/// The iCloud switch, and what the app is and owes.
struct SettingsView: View {
    @AppStorage(Catalog.syncSettingKey) private var syncsWithICloud = false
    @Environment(\.catalogSyncFailure) private var syncFailure
    @Environment(\.dismiss) private var dismiss

    private var isSignedInToICloud: Bool { FileManager.default.ubiquityIdentityToken != nil }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle("Sync with iCloud", isOn: $syncsWithICloud)
                } header: {
                    Text("Catalog")
                } footer: {
                    syncFooter
                }
                Section("About") {
                    LabeledContent("Version", value: AppInfo.version)
                    Text("An unofficial app for DiceKeys, the dice made by DiceKeys, LLC.")
                    Link("dicekeys.com", destination: AppInfo.diceKeysSite)
                }
                Section("Credits") {
                    ForEach(AppInfo.credits, id: \.self) { Text($0).font(.footnote) }
                }
            }
            .appBackdrop()
            .navigationTitle("Settings")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", systemImage: "checkmark") { dismiss() }
                }
            }
        }
    }

    private var syncFooter: some View {
        VStack(alignment: .leading) {
            Text(
                "Syncs each DiceKey's name and center die, and each key's kind, name, settings and public key, so your other devices list them. Never the dice or a secret: each device scans the DiceKey itself. Turning sync off keeps the iCloud copy until you delete it in iCloud storage settings."
            )
            if syncsWithICloud != Catalog.syncsThisLaunch {
                Text("Takes effect the next time the app opens.")
            }
            if let syncFailure {
                Text("iCloud sync couldn't start, so the catalog is on this device only for now: \(syncFailure)")
            }
            if syncsWithICloud && !isSignedInToICloud {
                Text("This device isn't signed in to iCloud, so nothing syncs.")
            }
        }
    }
}
