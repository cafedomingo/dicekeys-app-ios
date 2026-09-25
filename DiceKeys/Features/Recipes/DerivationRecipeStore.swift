//
//  DerivationRecipeStore.swift
//  DiceKeys
//
//  Created by Stuart Schechter on 2021/02/08.
//

import Foundation
import Observation

/// The user's saved recipes, persisted as JSON in `UserDefaults`.
@MainActor @Observable
final class DerivationRecipeStore {
    static let fieldNameSavedDerivationRecipes: String = "savedDerivationRecipes"

    @ObservationIgnored private let defaults: UserDefaults

    var savedDerivationRecipes: [DerivationRecipe] {
        didSet {
            if let json = try? DerivationRecipe.listToJson(savedDerivationRecipes) {
                defaults.set(json, forKey: Self.fieldNameSavedDerivationRecipes)
            }
        }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let json = defaults.string(forKey: Self.fieldNameSavedDerivationRecipes) ?? ""
        self.savedDerivationRecipes = json.isEmpty ? [] : ((try? DerivationRecipe.listFromJson(json)) ?? [])
    }

    func saveRecipe(_ recipeToSave: DerivationRecipe?) {
        guard let recipe = recipeToSave else { return }
        if savedDerivationRecipes.allSatisfy({ $0.id != recipe.id }) {
            savedDerivationRecipes = (savedDerivationRecipes + [recipe]).sorted { $0.id < $1.id }
        }
    }

    func removeRecipe(_ recipeId: String) {
        savedDerivationRecipes.removeAll { $0.id == recipeId }
    }

    func removeRecipe(_ recipe: DerivationRecipe?) {
        if let recipeId = recipe?.id {
            removeRecipe(recipeId)
        }
    }
}
