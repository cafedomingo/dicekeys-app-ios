//
//  RecipeSource.swift
//  DiceKeys
//
//  Created by Stuart Schechter on 2020/12/11.
//

/// What the derivation screen was opened with: a finished recipe, or a
/// template that still needs a sequence number.
enum RecipeSource: Hashable {
    case recipe(DerivationRecipe)
    case template(DerivationRecipe)

    // `==` is synthesized from `DerivationRecipe: Equatable`. A recipe's `id` is
    // built from all of its fields, so hashing it is consistent with `==`.
    func hash(into hasher: inout Hasher) {
        switch self {
        case .recipe(let recipe):
            hasher.combine(0)
            hasher.combine(recipe.id)
        case .template(let template):
            hasher.combine(1)
            hasher.combine(template.id)
        }
    }
}
