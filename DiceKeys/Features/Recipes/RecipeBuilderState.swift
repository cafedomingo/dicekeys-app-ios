//
//  RecipeBuilderState.swift
//  DiceKeys
//
//  Created by Stuart Schechter on 2020/12/11.
//

import Observation

enum RecipeBuilderProgress: Equatable {
    case incomplete
    case error(String)
    case ready(DerivationRecipe)

    var recipe: DerivationRecipe? {
        if case .ready(let derivationRecipe) = self { return derivationRecipe }
        return nil
    }
}

/// The output of a recipe builder, shared between the builder and the screen
/// that derives from the finished recipe.
@MainActor @Observable
final class RecipeBuilderState {
    var progress: RecipeBuilderProgress = .incomplete
}
