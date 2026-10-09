//
//  RawJsonRecipeModel.swift
//  DiceKeys
//

import Derivation
import Observation

/// The raw JSON sheet: a recipe typed or pasted whole. The type menu decides what the JSON
/// is derived as, unless the JSON declares a type the app knows, which then wins. The recipe
/// is parsed here, so its errors show in the sheet rather than after Done.
@MainActor @Observable
final class RawJsonRecipeModel: Identifiable {
    var type: DerivableType = .password { didSet { update() } }
    var name = "" { didSet { update() } }
    var json = "{}" { didSet { update() } }
    var showRiskAlert = true

    private(set) var declaredType: DerivableType?
    private(set) var progress: RecipeBuilderProgress = .incomplete

    init() {
        update()
    }

    private func update() {
        guard !json.isBlank else {
            declaredType = nil
            progress = .incomplete
            return
        }
        let declared = Self.declaredType(in: json)
        declaredType = declared
        if let declared, declared != type {
            type = declared  // re-enters update() with the matching type
            return
        }
        let recipe: String
        do {
            recipe = try json.canonicalizedRecipe()
        } catch {
            progress = .error(error.message)
            return
        }
        do {
            _ = try Recipe(json: recipe, type: type)
        } catch {
            progress = .error(error.localizedDescription)
            return
        }
        progress = .ready(DerivationRecipe(type: type, name: name, recipe: recipe))
    }

    /// The `type` field as a known type, or nil when absent, malformed or unknown.
    private static func declaredType(in json: String) -> DerivableType? {
        guard let fields = try? RecipeJsonParser.parseObject(json),
            case .string(let quoted) = fields.first(where: { $0.name == "type" })?.value,
            let text = try? RecipeJsonParser.decodeString(quoted: quoted)
        else { return nil }
        return DerivableType(rawValue: text)
    }
}
