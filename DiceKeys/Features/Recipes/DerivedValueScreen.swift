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
            do {
                derivedValue = try recipe?.derivedValue(diceKey: diceKey)
                derivationError = nil
            } catch {
                derivedValue = nil
                derivationError = error.localizedDescription
            }
        }
        .onAppear {
            outputFormat = defaultOutputFormat
        }
    }

    /// Templates for PGP, SSH, and wallets open on the format their users expect.
    private var defaultOutputFormat: DerivedValueView {
        guard let recipe, let derivedValue else { return .JSON }
        if let purpose = recipe.purpose() {
            if purpose == "pgp" && recipe.type == .SigningKey {
                return .OpenPGPPrivateKey
            } else if purpose == "ssh" && recipe.type == .SigningKey {
                return .OpenSSHPrivateKey
            } else if purpose == "wallet" && recipe.type == .Secret && derivedValue.views.contains(.BIP39) {
                return .BIP39
            }
        }
        return derivedValue.views.first ?? .JSON
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
