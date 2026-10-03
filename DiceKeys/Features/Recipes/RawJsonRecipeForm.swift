//
//  RawJsonRecipeForm.swift
//  DiceKeys
//

import Derivation
import SwiftUI

/// A recipe typed whole. The type menu follows a declared `type` and locks while one is
/// present.
struct RawJsonRecipeForm: View {
    @Bindable var model: RawJsonRecipeModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Form {
            Section {
                Picker("Type", selection: $model.type) {
                    ForEach(DerivableType.allCases) { Text($0.description).tag($0) }
                }
                .pickerStyle(.menu)
                .disabled(model.declaredType != nil)
                TextField("Recipe name", text: $model.name)
                    .plainTextEntry()
                TextField("Raw JSON", text: $model.json, axis: .vertical)
                    .lineLimit(4...)
                    .plainTextEntry()
                Text(
                    "Even the smallest change to any field changes the entire " + model.type.descriptionForRecipeBuilder
                )
                .font(.footnote)
                .foregroundStyle(.secondary)
                if case .error(let errorString) = model.progress {
                    Text(errorString).font(.footnote).foregroundStyle(Color.Interface.errorText)
                }
            }
        }
        .formStyle(.grouped)
        .alert("Edit Raw JSON", isPresented: $model.showRiskAlert) {
            Button("I accept the risk") { model.showRiskAlert = false }
            Button("Cancel", role: .destructive) { dismiss() }
        } message: {
            Text(
                "Entering a recipe in raw JSON format can be dangerous.\n\nIf you enter a recipe provided by someone else, it could be a trick to get you to re-create a secret you use for another application or purpose.\n\nIf you generate the recipe yourself and forget even a single character, you will be unable to re-generate the same secret again. (Saving the recipe won't help you if you lose the device(s) it's saved on.)"
            )
        }
    }
}

#Preview {
    RawJsonRecipeForm(model: RawJsonRecipeModel())
}
