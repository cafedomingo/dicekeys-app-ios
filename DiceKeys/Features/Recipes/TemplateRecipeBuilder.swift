//
//  TemplateRecipeBuilder.swift
//  DiceKeys
//
//  Created by Stuart Schechter on 2020/12/11.
//

import SwiftUI

/// Builds a recipe from one of the built-in templates plus a sequence number.
struct TemplateRecipeBuilder: View {
    let template: DerivationRecipe
    let builderState: RecipeBuilderState

    @State private var sequenceNumber: Int = 1

    var body: some View {
        // This app will remember that you've created a password for
        // X before, but you'll need to add this option if you use
        // the DiceKeys app on another device
        SequenceNumberField(sequenceNumber: $sequenceNumber)
            .onChange(of: sequenceNumber, initial: true) { _, sequenceNumber in
                builderState.progress = .ready(DerivationRecipe(
                    template: template,
                    sequenceNumber: sequenceNumber,
                    lengthInChars: template.lengthInChars(),
                    lengthInBytes: template.lengthInBytes()
                ))
            }
    }
}

#Preview {
    TemplateRecipeBuilder(template: derivationRecipeTemplates[0], builderState: RecipeBuilderState())
        .padding()
}
