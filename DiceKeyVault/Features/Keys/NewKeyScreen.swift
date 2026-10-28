//
//  NewKeyScreen.swift
//  DiceKeyVault
//

import Derivation
import KeyFormats
import SwiftData
import SwiftUI

/// Making a key is looking it up: a kind and a name give the key at once, so its public
/// half updates as you type, and Save only adds it to the catalog.
struct NewKeyScreen: View {
    let diceKey: DiceKey
    let onSaved: (KeyEntry) -> Void

    @State private var kind = KeyKind.ssh
    @State private var name = ""
    @State private var style = PassphraseStyle.standard
    @State private var error: PresentableError?
    /// A passphrase or recovery phrase has no public half, so its preview is the secret,
    /// shown only on request and hidden whenever others could see it.
    @State private var isSecretShown = false
    @Environment(\.isSceneCaptured) private var isSceneCaptured
    @Environment(\.modelContext) private var context

    private static let updates = "updates as you type"
    /// Typing scrolls this row to the top, so the preview under it clears the keyboard.
    private static let nameRow = "name"

    private var recipe: KeyRecipe? { try? KeyRecipe(kind: kind, name: name, style: style) }

    var body: some View {
        let preview = recipe.map { DerivedKey.derive(seed: diceKey.seed, recipe: $0) }
        let existing = recipe.flatMap { try? context.entry(for: $0, diceKeyID: diceKey.id) }
        ScrollViewReader { proxy in
            Form {
                Section {
                    Picker("Kind", selection: $kind) {
                        ForEach(KeyKind.allCases, id: \.self) { kind in
                            Label(kind.title, systemImage: kind.symbol).tag(kind)
                        }
                    }
                    TextField("Name", text: $name, prompt: Text("github, homelab, nas"))
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .id(Self.nameRow)
                    if let existing {
                        Button("Open it", systemImage: "arrow.forward") { onSaved(existing) }
                    }
                } footer: {
                    if existing == nil {
                        Text("The name is part of the key. One changed letter is a different key.")
                    } else {
                        Text("You already have this key.")
                    }
                }
                if let preview, kind.hasPublicKey {
                    ForEach(Array(preview.algorithms.enumerated()), id: \.element.type) { index, algorithm in
                        if let publicKey = algorithm.publicKey {
                            let display = kind.display(of: algorithm.type)
                            PublicKeySection(
                                publicKey: publicKey, fingerprint: algorithm.fingerprint,
                                title: index == 0 ? "\(display.title) · \(Self.updates)" : display.title,
                                note: display.note, foldedLines: display.foldedLines)
                        }
                    }
                } else if let secret = preview?.algorithms.first?.secret {
                    Section("\(kind.secretTitle) · \(Self.updates)") {
                        if isSecretShown {
                            SecretView(kind: kind, secret: secret)
                            SecretActions(kind: kind, secret: secret)
                        }
                        Button(isSecretShown ? "Hide" : "Show", systemImage: isSecretShown ? "eye.slash" : "eye") {
                            isSecretShown.toggle()
                        }
                        .disabled(isSceneCaptured)
                    }
                }
                if kind == .passphrase {
                    PassphraseStyleSection(style: $style)
                }
            }
            .centeredContent()
            .onChange(of: name) {
                withAnimation { proxy.scrollTo(Self.nameRow, anchor: .top) }
            }
        }
        .concealsWhenExposed($isSecretShown)
        .appBackdrop()
        .navigationTitle("New key")
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save", systemImage: "checkmark") { save(preview) }
                    .primaryAction()
                    .disabled(preview == nil || existing != nil)
            }
        }
        .errorAlert($error)
    }

    private func save(_ key: DerivedKey?) {
        guard let key else { return }
        do {
            onSaved(try context.addEntry(for: key, diceKeyID: diceKey.id))
        } catch {
            self.error = PresentableError(title: "Couldn't Save", error: error)
        }
    }
}

struct PassphraseStyleSection: View {
    @Binding var style: PassphraseStyle

    var body: some View {
        Section {
            Picker("Style", selection: $style.isMemorable) {
                Text("Random").tag(false)
                Text("Memorable").tag(true)
            }
            .pickerStyle(.segmented)
            if style.isMemorable {
                CountSlider(unit: "words", count: $style.wordCount, range: PassphraseStyle.memorableWords)
                Toggle("Add digits and an uppercase word", isOn: $style.addsDigitsAndUppercase)
            } else {
                CountSlider(unit: "characters", count: $style.characterCount, range: PassphraseStyle.randomLengths)
                Toggle("Include symbols", isOn: $style.includesSymbols)
            }
        } footer: {
            VStack(alignment: .leading, spacing: .space2) {
                StrengthBar(bits: style.bits)
                Text("About \(Int(style.bits)) bits. These settings are part of the passphrase.")
            }
        }
    }
}

/// A whole-number slider labeled with its value, which drags quickly across a wide range.
private struct CountSlider: View {
    let unit: String
    @Binding var count: Int
    let range: ClosedRange<Int>

    var body: some View {
        VStack(alignment: .leading) {
            Text("\(count) \(unit)").monospacedDigit()
            Slider(
                value: Binding(get: { Double(count) }, set: { count = Int($0) }),
                in: Double(range.lowerBound)...Double(range.upperBound), step: 1
            ) {
                Text(unit.capitalized)
            } minimumValueLabel: {
                Text("\(range.lowerBound)")
            } maximumValueLabel: {
                Text("\(range.upperBound)")
            }
            .foregroundStyle(.secondary)
            .accessibilityValue("\(count) \(unit)")
        }
    }
}

/// Settable views of the style for the editor's controls.
extension PassphraseStyle {
    var isMemorable: Bool {
        get { if case .memorable = self { true } else { false } }
        set { self = newValue ? Self.standardMemorable : Self.standard }
    }

    var characterCount: Int {
        get { if case .random(let length, _) = self { length } else { 0 } }
        set { if case .random(_, let symbols) = self { self = .random(length: newValue, symbols: symbols) } }
    }

    var includesSymbols: Bool {
        get { if case .random(_, let symbols) = self { symbols } else { false } }
        set { if case .random(let length, _) = self { self = .random(length: length, symbols: newValue) } }
    }

    var wordCount: Int {
        get { if case .memorable(let words, _) = self { words } else { 0 } }
        set {
            if case .memorable(_, let extra) = self { self = .memorable(words: newValue, digitsAndUppercase: extra) }
        }
    }

    var addsDigitsAndUppercase: Bool {
        get { if case .memorable(_, let extra) = self { extra } else { false } }
        set {
            if case .memorable(let words, _) = self { self = .memorable(words: words, digitsAndUppercase: newValue) }
        }
    }
}
