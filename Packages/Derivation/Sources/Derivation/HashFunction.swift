//
//  HashFunction.swift
//  Derivation
//

/// The hash a recipe's `hashFunction` field may name. One case for now; adding one is a
/// case here and an implementation in the engine. An unknown name is an error, never a
/// fallback, because the name is part of what gets hashed.
public enum HashFunction: String, Sendable {
    case blake2b = "BLAKE2b"
}

extension HashFunction {
    /// Stretches a seed into `outputLength` bytes, salted by `info` (the type string followed
    /// by the recipe text).
    func derive(seed: [UInt8], info: [UInt8], outputLength: Int) -> [UInt8] {
        switch self {
        case .blake2b:
            return HKDFBlake2b.derive(seed: seed, info: info, outputLength: outputLength)
        }
    }
}
