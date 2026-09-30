//
//  DerivationError.swift
//  Derivation
//

import Foundation

/// Why a recipe cannot be used. The messages are shown to the user, so they say what to
/// change.
public enum DerivationError: Error, Equatable, Sendable, LocalizedError {
    case recipeNotAnObject
    case invalidJson(String)
    case duplicateField(String)
    case wrongType(field: String, expected: String)
    case outOfRange(field: String, allowed: ClosedRange<Int>)
    case typeMismatch(recipe: String, requested: DerivableType)
    case invalidAlgorithm(String)
    case unsupportedHashFunction(String)
    case unknownWordList(String)
    case lengthMustBe32(DerivableType)
    case bitsAndWordsConflict

    public var errorDescription: String? {
        switch self {
        case .recipeNotAnObject:
            return "A recipe must be a JSON object, such as {\"purpose\":\"example\"}"
        case .invalidJson(let reason):
            return reason
        case .duplicateField(let name):
            return "The field \(name) appears more than once"
        case .wrongType(let field, let expected):
            return "\(field) must be \(expected)"
        case .outOfRange(let field, let allowed):
            if allowed.upperBound == Int.max {
                return "\(field) must be at least \(allowed.lowerBound)"
            }
            return "\(field) must be between \(allowed.lowerBound) and \(allowed.upperBound)"
        case .typeMismatch(let recipe, let requested):
            return "The recipe's type is \(recipe); this needs a \(requested.rawValue)"
        case .invalidAlgorithm(let name):
            return "The algorithm \(name) does not apply here"
        case .unsupportedHashFunction(let name):
            return "The hash function \(name) is not supported; only BLAKE2b is"
        case .unknownWordList(let name):
            return "Unknown word list \(name)"
        case .lengthMustBe32(let type):
            return "A \(type.rawValue) is always 32 bytes; leave lengthInBytes out or set it to 32"
        case .bitsAndWordsConflict:
            return "lengthInBits and lengthInWords disagree; give one or the other"
        }
    }
}
