//
//  BLAKE2b.swift
//  BLAKE2
//
//  BLAKE2b as specified in RFC 7693, including keyed hashing, which the derivation uses in
//  place of HMAC. Salt and personalization are always zero here, so the parameter block is
//  the digest length, the key length, fanout 1 and depth 1.
//

public struct BLAKE2b: Sendable {
    public static let blockSize = 128
    public static let maximumDigestLength = 64
    public static let maximumKeyLength = 64

    private static let iv: [UInt64] = [
        0x6a09_e667_f3bc_c908, 0xbb67_ae85_84ca_a73b, 0x3c6e_f372_fe94_f82b, 0xa54f_f53a_5f1d_36f1,
        0x510e_527f_ade6_82d1, 0x9b05_688c_2b3e_6c1f, 0x1f83_d9ab_fb41_bd6b, 0x5be0_cd19_137e_2179
    ]

    private static let sigma: [[Int]] = [
        [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15],
        [14, 10, 4, 8, 9, 15, 13, 6, 1, 12, 0, 2, 11, 7, 5, 3],
        [11, 8, 12, 0, 5, 2, 15, 13, 10, 14, 3, 6, 7, 1, 9, 4],
        [7, 9, 3, 1, 13, 12, 11, 14, 2, 6, 5, 10, 4, 0, 15, 8],
        [9, 0, 5, 7, 2, 4, 10, 15, 14, 1, 11, 12, 6, 8, 3, 13],
        [2, 12, 6, 10, 0, 11, 8, 3, 4, 13, 7, 5, 15, 14, 1, 9],
        [12, 5, 1, 15, 14, 13, 4, 10, 0, 7, 6, 3, 9, 2, 8, 11],
        [13, 11, 7, 14, 12, 1, 3, 9, 5, 0, 15, 4, 8, 6, 2, 10],
        [6, 15, 14, 9, 11, 3, 0, 8, 12, 2, 13, 7, 1, 4, 10, 5],
        [10, 2, 8, 4, 7, 6, 1, 5, 15, 11, 9, 14, 3, 12, 13, 0]
    ]

    public let digestLength: Int

    private var state: [UInt64]
    /// The block being filled. A full block is compressed only when more input arrives,
    /// because the last block, full or not, is compressed with the final flag.
    private var block: [UInt8]
    private var pending = 0
    private var counterLow: UInt64 = 0
    private var counterHigh: UInt64 = 0

    public init(digestLength: Int = 64, key: [UInt8] = []) {
        precondition((1...Self.maximumDigestLength).contains(digestLength), "BLAKE2b digests are 1 to 64 bytes")
        precondition(key.count <= Self.maximumKeyLength, "BLAKE2b keys are at most 64 bytes")
        self.digestLength = digestLength
        state = Self.iv
        state[0] ^= 0x0101_0000 ^ (UInt64(key.count) << 8) ^ UInt64(digestLength)
        block = [UInt8](repeating: 0, count: Self.blockSize)
        // A key is hashed as a first block padded with zeros; it counts as 128 bytes of input.
        if !key.isEmpty {
            block.replaceSubrange(0..<key.count, with: key)
            pending = Self.blockSize
        }
    }

    public mutating func update(_ input: some Sequence<UInt8>) {
        for byte in input {
            if pending == Self.blockSize {
                addToCounter(UInt64(Self.blockSize))
                compress(final: false)
                pending = 0
            }
            block[pending] = byte
            pending += 1
        }
    }

    /// The digest of everything given to `update` so far. The value is unchanged, so more
    /// input can follow and produce a longer message's digest.
    public func finalize() -> [UInt8] {
        var copy = self
        copy.addToCounter(UInt64(copy.pending))
        for index in copy.pending..<Self.blockSize {
            copy.block[index] = 0
        }
        copy.compress(final: true)
        var digest = [UInt8]()
        digest.reserveCapacity(Self.maximumDigestLength)
        for word in copy.state {
            for shift in stride(from: 0, to: 64, by: 8) {
                digest.append(UInt8(truncatingIfNeeded: word >> UInt64(shift)))
            }
        }
        return Array(digest.prefix(digestLength))
    }

    public static func hash(_ message: some Sequence<UInt8>, key: [UInt8] = [], digestLength: Int = 64) -> [UInt8] {
        var hasher = BLAKE2b(digestLength: digestLength, key: key)
        hasher.update(message)
        return hasher.finalize()
    }

    private mutating func addToCounter(_ count: UInt64) {
        let (sum, overflow) = counterLow.addingReportingOverflow(count)
        counterLow = sum
        if overflow {
            counterHigh &+= 1
        }
    }

    private mutating func compress(final: Bool) {
        var message = [UInt64](repeating: 0, count: 16)
        for word in 0..<16 {
            var value: UInt64 = 0
            for byte in 0..<8 {
                value |= UInt64(block[word * 8 + byte]) << UInt64(8 * byte)
            }
            message[word] = value
        }
        var v = state + Self.iv
        v[12] ^= counterLow
        v[13] ^= counterHigh
        if final {
            v[14] = ~v[14]
        }
        for round in 0..<12 {
            let s = Self.sigma[round % 10]
            Self.mix(&v, 0, 4, 8, 12, message[s[0]], message[s[1]])
            Self.mix(&v, 1, 5, 9, 13, message[s[2]], message[s[3]])
            Self.mix(&v, 2, 6, 10, 14, message[s[4]], message[s[5]])
            Self.mix(&v, 3, 7, 11, 15, message[s[6]], message[s[7]])
            Self.mix(&v, 0, 5, 10, 15, message[s[8]], message[s[9]])
            Self.mix(&v, 1, 6, 11, 12, message[s[10]], message[s[11]])
            Self.mix(&v, 2, 7, 8, 13, message[s[12]], message[s[13]])
            Self.mix(&v, 3, 4, 9, 14, message[s[14]], message[s[15]])
        }
        for index in 0..<8 {
            state[index] ^= v[index] ^ v[index + 8]
        }
    }

    private static func mix(_ v: inout [UInt64], _ a: Int, _ b: Int, _ c: Int, _ d: Int, _ x: UInt64, _ y: UInt64) {
        v[a] = v[a] &+ v[b] &+ x
        v[d] = rotateRight(v[d] ^ v[a], by: 32)
        v[c] = v[c] &+ v[d]
        v[b] = rotateRight(v[b] ^ v[c], by: 24)
        v[a] = v[a] &+ v[b] &+ y
        v[d] = rotateRight(v[d] ^ v[a], by: 16)
        v[c] = v[c] &+ v[d]
        v[b] = rotateRight(v[b] ^ v[c], by: 63)
    }

    private static func rotateRight(_ value: UInt64, by bits: UInt64) -> UInt64 {
        (value >> bits) | (value << (64 - bits))
    }
}
