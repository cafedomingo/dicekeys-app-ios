//
//  CustomRecipeModel.swift
//  DiceKeys
//

import Derivation
import Observation

/// Builds a custom recipe from a purpose for every type but Password, which has its own
/// sheet. Every edit recomputes `progress`.
@MainActor @Observable
final class CustomRecipeModel: Identifiable {
    /// Shown in the form's section title, so the limit the model enforces and the one the
    /// user reads are the same.
    static let lengthInBytesEntryRange = 16...999

    let type: DerivableType

    private(set) var progress: RecipeBuilderProgress = .incomplete

    var purposeString: String = "" { didSet { update() } }
    var sequenceNumber: Int = 1 { didSet { update() } }
    var lengthInBytes: Int = 0 { didSet { update() } }

    /// Text-field view of `lengthInBytes`: empty means the default length;
    /// values outside `lengthInBytesEntryRange` are ignored.
    var lengthInBytesEntry: Int? {
        get { lengthInBytes == 0 ? nil : lengthInBytes }
        set {
            guard let newValue else {
                lengthInBytes = 0
                return
            }
            if Self.lengthInBytesEntryRange.contains(newValue) { lengthInBytes = newValue }
        }
    }

    init(type: DerivableType) {
        self.type = type
        update()
    }

    private func update() {
        guard !purposeString.isBlank else {
            progress = .incomplete
            return
        }
        let recipe = getRecipeJson(
            purpose: purposeString.trim(), sequenceNumber: sequenceNumber,
            lengthInBytes: type == .secret ? lengthInBytes : nil)
        progress = .ready(DerivationRecipe(type: type, name: purposeString, recipe: recipe))
    }
}
