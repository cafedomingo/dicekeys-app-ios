//
//  DerivationEngine.swift
//  Derivation
//

/// What turns a seed and a recipe into a derived value. The output is the value's JSON in
/// the reference layout (see `Derived.swift`), because that is the one form every
/// implementation must agree on byte for byte.
///
/// This seam exists so the vendored C++ and its Swift replacement can be run over the same
/// vectors side by side. It goes away with the C++.
protocol DerivationEngine: Sendable {
    func derive(_ type: DerivableType, seed: String, recipe: String) throws(DerivationError) -> String
}

let defaultEngine: any DerivationEngine = LegacyEngine()
