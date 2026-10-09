//
//  PasswordRecipeModel.swift
//  DiceKeys
//

import Derivation
import Observation

/// The password sheet: the user's choices, the recipe they write, and what the sheet shows
/// about it. The seed is injected so the live preview derives here and a test can drive it
/// without the memory store.
@MainActor @Observable
final class PasswordRecipeModel: Identifiable {
    private let seed: String?

    var purpose = "" { didSet { if purpose != oldValue { update() } } }
    var sequenceNumber = 1 { didSet { if sequenceNumber != oldValue { update() } } }
    var choices = PasswordRecipeChoices() { didSet { if choices != oldValue { update() } } }

    private(set) var progress: RecipeBuilderProgress = .incomplete
    private(set) var preview: String?
    /// The strength of everything the choices ask for.
    private(set) var bits: Double = 0
    /// The whole entries that always survive the maximum and their bits, or nil when the
    /// maximum cuts none. A digit separator can be cut with the word after it, so none count.
    private(set) var guarantee: (entries: Int, bits: Double)?
    /// What the bar shows: the guarantee when there is one, since that is what the user is
    /// sure to get.
    private(set) var scoredBits: Double = 0

    init(seed: String?) {
        self.seed = seed
        update()
    }

    /// 1Password shows no bar for a PIN, and neither does this.
    var showsStrength: Bool { choices.kind != .pin }

    private func update() {
        let list = choices.wordList
        bits = PasswordStrength.bits(list: list, entries: choices.entries, separator: choices.effectiveSeparator)
        guarantee = guaranteedEntries().map { (entries: $0, bits: list.bits(forWords: $0)) }
        scoredBits = guarantee?.bits ?? bits

        preview = nil
        let trimmed = purpose.trim()
        guard !trimmed.isEmpty else {
            progress = .incomplete
            return
        }
        let json = getRecipeJson(purpose: trimmed, sequenceNumber: sequenceNumber, choices: choices)
        progress = .ready(DerivationRecipe(type: .password, name: trimmed, recipe: json))
        guard let seed else { return }
        do {
            preview = try Password.derive(seed: seed, recipe: json).password
        } catch {
            // The writer only produces recipes the parser accepts; a failure here is a bug
            // worth seeing on screen rather than hiding.
            progress = .error(error.localizedDescription)
        }
    }

    private func guaranteedEntries() -> Int? {
        guard choices.wordList.kind == .words, let maximum = choices.maximumCharacters else { return nil }
        let fit = PasswordStrength.guaranteedEntries(
            list: choices.wordList, entries: choices.entries, separator: choices.effectiveSeparator,
            maximumCharacters: maximum)
        return fit < choices.entries ? fit : nil
    }
}
