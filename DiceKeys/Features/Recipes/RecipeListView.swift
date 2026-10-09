//
//  RecipeListView.swift
//  DiceKeys
//

import Derivation
import SwiftUI

/// The list of saved, built-in, and custom recipes. Selecting one pushes the
/// derivation screen onto the root navigation stack.
struct RecipeListView: View {
    @Environment(AppRouter.self) private var router
    @Environment(DerivationRecipeStore.self) private var derivationRecipeStore

    /// Which custom sheet is up. One optional drives `.sheet(item:)`.
    private enum CustomSheet: Identifiable {
        case password(PasswordRecipeModel)
        case purpose(CustomRecipeModel)
        case rawJson(RawJsonRecipeModel)

        var id: ObjectIdentifier {
            switch self {
            case .password(let model): return ObjectIdentifier(model)
            case .purpose(let model): return ObjectIdentifier(model)
            case .rawJson(let model): return ObjectIdentifier(model)
            }
        }

        var title: String {
            switch self {
            case .password: return "Password"
            case .purpose(let model): return model.type.descriptionForRecipeBuilder.capitalized
            case .rawJson: return "Raw JSON"
            }
        }

        @MainActor var progress: RecipeBuilderProgress {
            switch self {
            case .password(let model): return model.progress
            case .purpose(let model): return model.progress
            case .rawJson(let model): return model.progress
            }
        }
    }

    @State private var customSheet: CustomSheet?
    @Environment(DiceKeyMemoryStore.self) private var diceKeyMemoryStore

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
                ForEach(DerivableType.allCases) { type in
                    Button(type.description) {
                        if type == .password {
                            customSheet = .password(
                                PasswordRecipeModel(seed: diceKeyMemoryStore.diceKeyLoaded?.toSeed()))
                        } else {
                            customSheet = .purpose(CustomRecipeModel(type: type))
                        }
                    }
                    .foregroundStyle(.primary)
                }
                Button("Raw JSON") { customSheet = .rawJson(RawJsonRecipeModel()) }
                    .foregroundStyle(.primary)
            }
        }
        .scrollEdgeEffectStyle(.soft, for: .top)
        .sheet(item: $customSheet) { sheet in
            CustomRecipeSheet(
                title: sheet.title, progress: sheet.progress, onDone: { router.push(.derive(.recipe($0))) },
                content: {
                    switch sheet {
                    case .password(let model): PasswordRecipeForm(model: model)
                    case .purpose(let model): CustomRecipeForm(model: model)
                    case .rawJson(let model): RawJsonRecipeForm(model: model)
                    }
                }
            )
            .presentationDetents([.medium, .large])
        }
    }
}

/// The navigation chrome around a custom recipe form: title, Cancel, and Done once there is
/// a recipe.
private struct CustomRecipeSheet<Content: View>: View {
    @Environment(\.dismiss) private var dismiss
    let title: String
    let progress: RecipeBuilderProgress
    let onDone: (DerivationRecipe) -> Void
    @ViewBuilder let content: Content

    var body: some View {
        NavigationStack {
            content
                .navigationTitle(title)
                .toolbarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { dismiss() }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") {
                            if let recipe = progress.recipe { onDone(recipe) }
                            dismiss()
                        }
                        .disabled(progress.recipe == nil)
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
