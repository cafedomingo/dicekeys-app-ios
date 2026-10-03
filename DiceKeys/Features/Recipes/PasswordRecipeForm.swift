//
//  PasswordRecipeForm.swift
//  DiceKeys
//

import Derivation
import SwiftUI

/// The password generator: the purpose, a live preview with its strength, a type menu with
/// the controls that type takes, and the sequence number. All arithmetic lives in the model.
struct PasswordRecipeForm: View {
    @Bindable var model: PasswordRecipeModel

    private var choices: PasswordRecipeChoices { model.choices }
    private var isEmoji: Bool { choices.memorableList == .emoji }
    private var errorString: String? {
        if case .error(let message) = model.progress { return message }
        return nil
    }

    var body: some View {
        Form {
            Section("What Is This Password For?") {
                TextField("purpose", text: $model.purpose)
                    .plainTextEntry()
            }
            previewSection
            Section {
                Picker("Type", selection: $model.choices.kind) {
                    ForEach(PasswordRecipeChoices.Kind.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                .pickerStyle(.menu)
                switch choices.kind {
                case .memorable: memorableControls
                case .random: randomControls
                case .pin: pinControls
                }
            }
            Section("Sequence Number") {
                SequenceNumberField(sequenceNumber: $model.sequenceNumber)
            }
        }
        .formStyle(.grouped)
    }

    @ViewBuilder private var previewSection: some View {
        if model.preview != nil || model.showsStrength || errorString != nil {
            Section {
                if let preview = model.preview {
                    ColoredSecretText(preview)
                        .font(.body.monospaced())
                        .lineLimit(4)
                        .minimumScaleFactor(0.6)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                if let errorString {
                    Text(errorString).font(.footnote).foregroundStyle(Color.Interface.errorText)
                }
                if model.showsStrength {
                    StrengthBar(band: model.band)
                    Text("\(model.band.label), \(choices.entries) \(unit), \(Int(model.bits)) bits")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    /// What the length counts, lowercase: words, emoji, characters or digits.
    private var unit: String {
        switch choices.kind {
        case .memorable: return isEmoji ? "emoji" : "words"
        case .random: return "characters"
        case .pin: return "digits"
        }
    }

    @ViewBuilder private var memorableControls: some View {
        Picker("Word List", selection: $model.choices.memorableList) {
            ForEach(PasswordRecipeChoices.memorableLists, id: \.self) { Text($0.menuTitle).tag($0) }
        }
        .pickerStyle(.menu)
        LabeledSlider(
            label: "\(choices.wordCount) \(unit.capitalized)", value: $model.choices.wordCount,
            range: PasswordRecipeChoices.wordCountRange)
        if isEmoji {
            Text(
                "Many sites reject non-ASCII passwords, and each emoji counts as up to four bytes against a site's length limit."
            )
            .font(.footnote)
            .foregroundStyle(.secondary)
        } else {
            Picker("Separator", selection: $model.choices.separator) {
                ForEach([Separator.hyphen, .space, .period, .comma, .underscore, .digits, .empty], id: \.self) {
                    Text($0.menuTitle).tag($0)
                }
            }
            .pickerStyle(.menu)
            Toggle("Capitalize", isOn: $model.choices.capitalize)
            LabeledContent("Maximum Characters") {
                TextField("none", value: $model.choices.maximumCharactersEntry, format: .number)
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.trailing)
            }
            if choices.maximumCharacters == nil {
                let range = PasswordRecipeChoices.maximumCharactersRange
                Text("A maximum is \(range.lowerBound) to \(range.upperBound) characters; other values are ignored.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            if let guarantee = model.guarantee, let maximum = choices.maximumCharacters {
                Text(
                    "\(maximum) characters guarantees only \(guarantee.entries) whole \(guarantee.entries == 1 ? "word" : "words"), \(Int(guarantee.bits)) bits."
                )
                .font(.footnote)
                .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder private var randomControls: some View {
        LabeledSlider(
            label: "\(choices.characterCount) \(unit.capitalized)", value: $model.choices.characterCount,
            range: PasswordRecipeChoices.characterCountRange)
        Toggle("Numbers", isOn: $model.choices.numbers)
        Toggle("Symbols", isOn: $model.choices.symbols)
    }

    @ViewBuilder private var pinControls: some View {
        LabeledSlider(
            label: "\(choices.pinLength) \(unit.capitalized)", value: $model.choices.pinLength,
            range: PasswordRecipeChoices.pinLengthRange)
        Text("A PIN is only as safe as the lockout behind it.")
            .font(.footnote)
            .foregroundStyle(.secondary)
    }
}

/// A slider over whole numbers with its current value as the label, as 1Password lays it out.
private struct LabeledSlider: View {
    let label: String
    @Binding var value: Int
    let range: ClosedRange<Int>

    var body: some View {
        LabeledContent(label) {
            Slider(
                value: Binding(get: { Double(value) }, set: { value = Int($0.rounded()) }),
                in: Double(range.lowerBound)...Double(range.upperBound), step: 1
            )
            .frame(maxWidth: 220)
            .accessibilityLabel("Length")
            .accessibilityValue(label)
        }
    }
}

extension WordList {
    /// How the sheet names the lists a memorable password may use.
    fileprivate var menuTitle: String {
        switch self {
        case .effLarge: return "EFF large, 7,776 words"
        case .en512: return "English, 512 short words"
        case .en1024: return "English, 1,024 words"
        case .emoji: return "Emoji"
        default: return rawValue
        }
    }
}

extension Separator {
    fileprivate var menuTitle: String {
        switch self {
        case .hyphen: return "Hyphens"
        case .space: return "Spaces"
        case .period: return "Periods"
        case .comma: return "Commas"
        case .underscore: return "Underscores"
        case .digits: return "Numbers"
        case .empty: return "None"
        }
    }
}

#Preview {
    NavigationStack {
        PasswordRecipeForm(model: PasswordRecipeModel(seed: DiceKey.example.toSeed()))
    }
}
