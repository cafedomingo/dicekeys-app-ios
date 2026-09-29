//
//  Recipe.swift
//  SeededCrypto
//

import Foundation
import SeededCryptoNative

/// Helpers over recipe JSON that need the reference implementation's parser.
public enum Recipe {
    /// The recipe with every optional parameter made explicit: exactly what the
    /// library hashes. Useful for showing users what a derivation depends on.
    public static func withAllOptionalParametersSpecified(_ recipe: String) throws -> String {
        try Native.string { out, err in dkc_recipe_with_all_optional_parameters_specified(recipe, out, err) }
    }

    /// The raw primary secret every other derivation is built from.
    public static func derivePrimarySecret(seedString: String, recipe: String) throws -> Data {
        try Native.bytes { out, err in dkc_recipe_derive_primary_secret(seedString, recipe, out, err) }
    }

    /// Version of the vendored libsodium.
    public static var sodiumVersion: String { Native.sodiumVersion }
}
