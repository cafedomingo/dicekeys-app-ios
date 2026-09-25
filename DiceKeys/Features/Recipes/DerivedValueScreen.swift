//
//  DerivedValueScreen.swift
//  DiceKeys
//
//  Created by Stuart Schechter on 2020/12/03.
//

import SwiftUI

/// Derives a password, key, or secret from the foreground DiceKey and shows it
/// in the chosen output format, with a QR code option.
struct DerivedValueScreen: View {
    let source: RecipeSource

    @Environment(DiceKeyMemoryStore.self) private var diceKeyMemoryStore

    @State private var builderState = RecipeBuilderState()
    @State private var outputFormat: DerivedValueView = .JSON
    @State private var derivedValue: (any DerivedValue)?
    @State private var derivationError: String?
    @State private var presentQrCode = false

    private var diceKey: DiceKey {
        diceKeyMemoryStore.diceKeyLoaded ?? DiceKey.Example
    }

    /// The finished recipe: either given directly, or produced by the builder.
    private var recipe: DerivationRecipe? {
        switch source {
        case .recipe(let recipe): return recipe
        case .template: return builderState.progress.recipe
        }
    }

    var body: some View {
        VStack(alignment: .center, spacing: 0) {
            RecipeCardView(source: source, builderState: builderState, recipe: recipe)
                .padding(.top, 10)
                .padding(.horizontal, 10)
                .layoutPriority(1)
            Spacer()
            if let derivedValue {
                DerivedValueOutputView(
                    diceKey: diceKey,
                    derivedValue: derivedValue,
                    format: $outputFormat,
                    onShowQrCode: { presentQrCode = true }
                )
            } else if let derivationError {
                Text(derivationError)
                    .foregroundStyle(.red)
                    .padding()
            }
        }
        .navigationTitle(recipe?.name ?? "Derive")
        .toolbarTitleDisplayMode(.inline)
        .sheet(isPresented: $presentQrCode) {
            DerivedValueQrCodeSheet(
                title: outputFormat.description,
                content: derivedValue?.valueForView(view: outputFormat) ?? ""
            )
            .presentationDetents([.medium, .large])
            .privacyCover()
        }
        .onChange(of: recipe, initial: true) { _, recipe in
            let hadValue = derivedValue != nil
            do {
                derivedValue = try recipe?.derivedValue(diceKey: diceKey)
                derivationError = nil
            } catch {
                derivedValue = nil
                derivationError = error.localizedDescription
            }
            // Choose the format once there is a value to choose for: on the first value, or
            // when the chosen format no longer applies. Editing a recipe otherwise keeps it.
            if let recipe, let derivedValue, !hadValue || !derivedValue.views.contains(outputFormat) {
                outputFormat = recipe.defaultOutputFormat(for: derivedValue)
            }
        }
    }
}

#Preview("Template") {
    NavigationStack {
        DerivedValueScreen(source: .template(derivationRecipeTemplates[1]))
    }
    .appEnvironment(AppModel.preview(diceKey: DiceKey.createFromRandom()))
}

#Preview("Saved recipe") {
    NavigationStack {
        DerivedValueScreen(source: .recipe(derivationRecipeTemplates[10]))
    }
    .appEnvironment(AppModel.preview(diceKey: DiceKey.createFromRandom()))
}
