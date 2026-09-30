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
