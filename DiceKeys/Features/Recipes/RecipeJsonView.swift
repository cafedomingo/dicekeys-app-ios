//
//  RecipeJsonView.swift
//  DiceKeys
//
//  Created by Stuart Schechter on 2020/12/11.
//

import SwiftUI

/// The canonical JSON of the recipe being built (or why it is not ready yet).
struct RecipeJsonView: View {
    let progress: RecipeBuilderProgress

    var body: some View {
        switch progress {
        case .incomplete:
            monospaced("Complete the recipe above to see the output")
                .foregroundStyle(.secondary)
        case .error(let errorString):
            monospaced(errorString)
                .foregroundStyle(.red)
        case .ready(let recipe):
            monospaced(recipe.recipe)
        }
    }

    private func monospaced(_ text: String) -> some View {
        Text(text)
            .font(.system(.footnote, design: .monospaced))
            .scaledToFit()
            .minimumScaleFactor(0.01)
            .fixedSize(horizontal: false, vertical: true)
            .lineLimit(1)
    }
}

#Preview {
    VStack {
        RecipeJsonView(progress: .incomplete)
        RecipeJsonView(progress: .error("Field does not contain a valid URL or domain list"))
        RecipeJsonView(progress: .ready(derivationRecipeTemplates[0]))
    }
    .padding()
}
