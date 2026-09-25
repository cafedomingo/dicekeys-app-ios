//
//  RecipeListView.swift
//  DiceKeys
//
//  Created by Angelos Veglektsis on 7/6/22.
//

import SwiftUI

/// The list of saved, built-in, and custom recipes. Selecting one pushes the
/// derivation screen onto the root navigation stack.
struct RecipeListView: View {
    @Environment(AppRouter.self) private var router
    @Environment(DerivationRecipeStore.self) private var derivationRecipeStore

    /// The recipe being built in the "Custom Recipe" sheet.
    @State private var customRecipeModel: CustomRecipeModel?

    var body: some View {
        List {
            if !derivationRecipeStore.savedDerivationRecipes.isEmpty {
                Section("Saved Recipes") {
                    ForEach(derivationRecipeStore.savedDerivationRecipes) { recipe in
                        NavigationLink(recipe.name, value: Route.derive(.recipe(recipe)))
                    }
                }
            }

            Section("Built-in Recipes") {
                ForEach(derivationRecipeTemplates) { template in
                    NavigationLink(template.name, value: Route.derive(.template(template)))
                }
            }

            Section("Custom Recipe") {
                ForEach(SeededCryptoRecipeType.allCases) { type in
                    Button(type.description) {
                        customRecipeModel = CustomRecipeModel(type: type)
                    }
                    .foregroundStyle(.primary)
                }
            }
        }
        .scrollEdgeEffectStyle(.soft, for: .top)
        .sheet(item: $customRecipeModel) { model in
            CustomRecipeSheet(model: model) { recipe in
                router.push(.derive(.recipe(recipe)))
            }
            .presentationDetents([.medium, .large])
            .privacyCover()
        }
    }
}

/// Builds a custom recipe from a web address, a purpose, or raw JSON.
private struct CustomRecipeSheet: View {
    @Environment(\.dismiss) private var dismiss
    let model: CustomRecipeModel
    let onDone: (DerivationRecipe) -> Void

    var body: some View {
        NavigationStack {
            CustomRecipeForm(model: model)
                .navigationTitle(model.type.descriptionForRecipeBuilder.capitalized)
                .toolbarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { dismiss() }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") {
                            if let recipe = model.progress.recipe {
                                onDone(recipe)
                            }
                            dismiss()
                        }
                        .disabled(model.progress.recipe == nil)
                    }
                }
        }
    }
}

#Preview {
    NavigationStack {
        RecipeListView()
    }
    .appEnvironment(AppModel.preview())
}
