//
//  HKDF.swift
//  Derivation
//

import BLAKE2

/// The key derivation the reference implementation built: RFC 5869's shape with keyed
/// BLAKE2b in place of HMAC, 32-byte blocks, and a zero salt.
///
///     PRK  = BLAKE2b(key: 32 zero bytes, message: seed)
///     T(i) = BLAKE2b(key: PRK, message: T(i-1) || info || i)      i = 1 ... ceil(L / 32)
///
/// `Recipe` bounds `outputLength` at 8160 bytes, so the one-byte counter never wraps.
enum HKDFBlake2b {
    static let blockSize = 32

    static func derive(seed: [UInt8], info: [UInt8], outputLength: Int) -> [UInt8] {
        precondition(outputLength <= 255 * blockSize, "HKDF output is at most 255 blocks")
        let pseudorandomKey = BLAKE2b.hash(seed, key: [UInt8](repeating: 0, count: blockSize), digestLength: blockSize)
        var output = [UInt8]()
        output.reserveCapacity(outputLength + blockSize)
        var previous = [UInt8]()
        var counter: UInt8 = 1
        while output.count < outputLength {
            var hasher = BLAKE2b(digestLength: blockSize, key: pseudorandomKey)
            hasher.update(previous)
            hasher.update(info)
            hasher.update([counter])
            previous = hasher.finalize()
            output.append(contentsOf: previous)
            counter &+= 1
        }
        return Array(output.prefix(outputLength))
    }
}
