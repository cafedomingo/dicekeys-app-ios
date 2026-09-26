//
//  CustomRecipeForm.swift
//  DiceKeys
//
//  Created by Stuart Schechter on 2020/12/11.
//

import SwiftUI

/// The form for `CustomRecipeModel`: source picker, the matching text fields,
/// optional length limits, and the sequence number.
struct CustomRecipeForm: View {
    @Bindable var model: CustomRecipeModel

    private var explanation: String {
        switch model.buildType {
        case .rawJson: return "Even the smallest change to any field changes the entire " + model.type.descriptionForRecipeBuilder
        case .hosts: return "Paste or enter the address of the website that will use this " + model.type.descriptionForRecipeBuilder
        case .purpose: return "Enter a purpose for the " + model.type.descriptionForRecipeBuilder
        }
    }

    var body: some View {
        Form {
            Section("What Is This Recipe For?") {
                Picker("Recipe type", selection: $model.buildType) {
                    Text("Web Address").tag(RecipeBuildType.hosts)
                    Text("Purpose").tag(RecipeBuildType.purpose)
                    Text("Raw JSON").tag(RecipeBuildType.rawJson)
                }
                .pickerStyle(.segmented)
                .labelsHidden()

                switch model.buildType {
                case .hosts:
                    TextField("https://example.com", text: $model.urlString)
                        .plainTextEntry()
                case .purpose:
                    TextField("purpose", text: $model.purposeString)
                        .plainTextEntry()
                case .rawJson:
                    TextField("Recipe name", text: $model.nameString)
                        .plainTextEntry()
                    TextField("Raw JSON", text: $model.rawJsonString, axis: .vertical)
                        .lineLimit(4)
                        .plainTextEntry()
                }

                Text(explanation)
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                if case let .error(errorString) = model.progress {
                    Text(errorString).font(.footnote).foregroundStyle(.red)
                }
            }

            if model.buildType != .rawJson {
                if model.type == .Password {
                    Section("Maximum Length, in Characters (8 - 999)") {
                        TextField("no length limit", value: $model.lengthInCharsEntry, format: .number)
                            .keyboardType(.numberPad)
                    }
                } else if model.type == .Secret {
                    Section("Length, in Bytes (16 - 999)") {
                        TextField("32", value: $model.lengthInBytesEntry, format: .number)
                            .keyboardType(.numberPad)
                    }
                }
                Section("Sequence Number") {
                    SequenceNumberField(sequenceNumber: $model.sequenceNumber)
                }
            }
        }
        .formStyle(.grouped)
        .alert("Edit Raw JSON", isPresented: $model.showRawJsonAlert) {
            Button("I accept the risk") {
                model.showRawJsonAlert = false
            }
            Button("Cancel", role: .destructive) {
                model.showRawJsonAlert = false
                model.buildType = .hosts
            }
        } message: {
            Text("Entering a recipe in raw JSON format can be dangerous.\n\nIf you enter a recipe provided by someone else, it could be a trick to get you to re-create a secret you use for another application or purpose.\n\nIf you generate the recipe yourself and forget even a single character, you will be unable to re-generate the same secret again. (Saving the recipe won't help you if you lose the device(s) it's saved on.)")
        }
    }
}

private extension View {
    /// Text entry without autocorrection or automatic capitalization.
    func plainTextEntry() -> some View {
        self
            .autocorrectionDisabled()
            .font(.body)
            .textInputAutocapitalization(.never)
            .keyboardType(.alphabet)
    }
}

#Preview {
    CustomRecipeForm(model: CustomRecipeModel(type: .Password))
}
