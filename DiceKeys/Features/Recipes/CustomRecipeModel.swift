//
//  CustomRecipeModel.swift
//  DiceKeys
//

import Derivation
import Observation

enum RecipeBuildType: CaseIterable {
    case purpose, rawJson
}

/// Builds a custom recipe from a purpose string or raw JSON.
/// Every edit recomputes `progress`.
@MainActor @Observable
final class CustomRecipeModel: Identifiable {
    /// Shown in the form's section titles, so the limit the model enforces and the one the
    /// user reads are the same.
    static let lengthInCharsEntryRange = 8...999
    static let lengthInBytesEntryRange = 16...999

    let type: DerivableType

    private(set) var progress: RecipeBuilderProgress = .incomplete

    var buildType: RecipeBuildType = .purpose {
        didSet {
            update()
            if buildType == .rawJson {
                showRawJsonAlert = true
            }
        }
    }
    var purposeString: String = "" { didSet { update() } }
    var rawJsonString: String = "{}" { didSet { update() } }
    var nameString: String = "" { didSet { update() } }
    var sequenceNumber: Int = 1 { didSet { update() } }
    var lengthInChars: Int = 0 { didSet { update() } }
    var lengthInBytes: Int = 0 { didSet { update() } }

    var showRawJsonAlert: Bool = false

    /// Text-field view of `lengthInChars`: empty means "no limit"; values
    /// outside `lengthInCharsEntryRange` are ignored.
    var lengthInCharsEntry: Int? {
        get { lengthInChars == 0 ? nil : lengthInChars }
        set {
            guard let newValue else { lengthInChars = 0; return }
            if Self.lengthInCharsEntryRange.contains(newValue) { lengthInChars = newValue }
        }
    }

    /// Text-field view of `lengthInBytes`: empty means the default length;
    /// values outside `lengthInBytesEntryRange` are ignored.
    var lengthInBytesEntry: Int? {
        get { lengthInBytes == 0 ? nil : lengthInBytes }
        set {
            guard let newValue else { lengthInBytes = 0; return }
            if Self.lengthInBytesEntryRange.contains(newValue) { lengthInBytes = newValue }
        }
    }

    var name: String {
        switch buildType {
        case .purpose: return purposeString
        case .rawJson: return nameString
        }
    }

    init(type: DerivableType) {
        self.type = type
        update()
    }

    private func update() {
        let source = buildType == .purpose ? purposeString : rawJsonString
        guard !source.isBlank else {
            progress = .incomplete
            return
        }

        let recipe: String
        let lengthInChars = type == .password ? lengthInChars : 0
        let lengthInBytes = type == .secret ? lengthInBytes : 0

        switch buildType {
        case .purpose:
            recipe = getRecipeJson(purpose: purposeString.trim(), sequenceNumber: sequenceNumber, lengthInChars: lengthInChars, lengthInBytes: lengthInBytes)
        case .rawJson:
            do {
                recipe = try rawJsonString.canonicalizedRecipe()
            } catch {
                progress = .error(error.message)
                return
            }
        }

        progress = .ready(DerivationRecipe(type: type, name: name, recipe: recipe))
    }
}
