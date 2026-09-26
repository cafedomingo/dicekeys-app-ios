//
//  RecipeCardView.swift
//  DiceKeys
//

import SwiftUI

/// The recipe section of `DerivedValueScreen`: the builder (for templates),
/// the recipe's canonical JSON, and the save/remove button.
/// Content only: no glass, the system group box material is enough.
struct RecipeCardView: View {
    let source: RecipeSource
    let builderState: RecipeBuilderState
    let recipe: DerivationRecipe?

    @Environment(DerivationRecipeStore.self) private var recipeStore

    private var isSaved: Bool {
        guard let recipe else { return false }
        return recipeStore.savedDerivationRecipes.contains { $0.id == recipe.id }
    }

    private var progressToShow: RecipeBuilderProgress {
        switch source {
        case .recipe(let recipe): return .ready(recipe)
        case .template: return builderState.progress
        }
    }

    var body: some View {
        GroupBox {
            VStack(alignment: .leading) {
                if case .template(let template) = source {
                    TemplateRecipeBuilder(template: template, builderState: builderState)
                }
                Divider().hideIf(recipe == nil)
                Text("Internal representation of your recipe").hideIf(recipe == nil)
                    .scaledToFit()
                    .minimumScaleFactor(0.01)
                    .fixedSize(horizontal: false, vertical: true)
                    .lineLimit(1)
                RecipeJsonView(progress: progressToShow).padding(.top, 1)
                Divider()
                HStack {
                    Spacer()
                    Button(isSaved ? "Remove recipe from menu" : "Save recipe in the menu") {
                        if isSaved {
                            recipeStore.removeRecipe(recipe)
                        } else {
                            recipeStore.saveRecipe(recipe)
                        }
                    }
                    .showIf(recipe != nil)
                    Spacer()
                }
            }
        } label: {
            Text("Recipe\(recipe == nil ? "" : " for \(recipe?.name ?? "")")")
                .font(.headline)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
        }
    }
}

#Preview {
    RecipeCardView(source: .template(derivationRecipeTemplates[0]), builderState: RecipeBuilderState(), recipe: derivationRecipeTemplates[0])
        .padding()
        .appEnvironment(AppModel.preview())
}
