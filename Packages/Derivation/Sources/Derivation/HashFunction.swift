//
//  HashFunction.swift
//  Derivation
//

/// The hash a recipe's `hashFunction` field may name. An unknown name is an error, not a
/// fallback, because the recipe text is hashed.
public enum HashFunction: String, Sendable {
    case blake2b = "BLAKE2b"
}

extension HashFunction {
    func derive(seed: [UInt8], info: [UInt8], outputLength: Int) -> [UInt8] {
        switch self {
        case .blake2b:
            return HKDFBlake2b.derive(seed: seed, info: info, outputLength: outputLength)
        }
    }
}
