//
//  SettingsView.swift
//  DiceKeyVault
//

import SwiftData
import SwiftUI
import UniformTypeIdentifiers

/// The iCloud switch, and what the app is and owes.
struct SettingsView: View {
    @AppStorage(Catalog.syncSettingKey) private var syncsWithICloud = false
    @Environment(\.catalogSyncFailure) private var syncFailure
    @Environment(\.dismiss) private var dismiss
    @Query private var records: [DiceKeyRecord]
    @Query private var entries: [KeyEntry]
    @State private var isImporting = false
    @State private var catalogToImport: CatalogFile?
    @State private var error: PresentableError?

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
                let export = Result { try CatalogFile(records: records, entries: entries) }
                Section {
                    switch export {
                    case .success(let file):
                        ShareLink(item: CatalogExport(file: file), preview: SharePreview(CatalogExport.filename)) {
                            Label("Export catalog", systemImage: "square.and.arrow.up")
                        }
                    case .failure:
                        Button("Export catalog", systemImage: "square.and.arrow.up") {}
                            .disabled(true)
                    }
                    Button("Import catalog", systemImage: "square.and.arrow.down") { isImporting = true }
                } footer: {
                    VStack(alignment: .leading) {
                        Text(
                            "A readable file of your DiceKeys' names and the keys you made, to keep anywhere you like instead of, or as well as, iCloud. Like the catalog, it holds no secret."
                        )
                        if case .failure(let error) = export {
                            Text(error.localizedDescription)
                        }
                    }
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
            .fileImporter(isPresented: $isImporting, allowedContentTypes: [.json]) { result in
                do {
                    let url = try result.get()
                    let isAccessing = url.startAccessingSecurityScopedResource()
                    defer { if isAccessing { url.stopAccessingSecurityScopedResource() } }
                    catalogToImport = try CatalogFile(json: Data(contentsOf: url))
                } catch {
                    self.error = PresentableError(title: "Not a Catalog", error: error)
                }
            }
            .importsCatalog($catalogToImport)
            .errorAlert($error)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done", systemImage: "xmark") { dismiss() }
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
