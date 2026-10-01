//
//  BLAKE2b.swift
//  BLAKE2
//

/// BLAKE2b (RFC 7693) with keyed hashing. Salt and personalization are always zero.
public struct BLAKE2b: Sendable {
    public static let blockSize = 128
    public static let maximumDigestLength = 64
    public static let maximumKeyLength = 64

    /// The block as 64-bit words (RFC 7693 section 2.2).
    private static let wordsPerBlock = blockSize / 8
    /// RFC 7693 section 3.2: BLAKE2b mixes in 12 rounds, cycling through the ten sigma rows.
    private static let rounds = 12
    /// Parameter block word 0 above the digest and key length bytes: fanout 1 and depth 1,
    /// which is sequential hashing (RFC 7693 section 2.5).
    private static let sequentialModeParameters: UInt64 = 0x0101_0000

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
    /// The block as 16 little-endian words, kept between blocks to avoid an allocation each.
    private var words = [UInt64](repeating: 0, count: Self.wordsPerBlock)
    private var pending = 0
    private var counterLow: UInt64 = 0
    /// Reached only past 2^64 bytes, so no test can pin it; the carry is kept for RFC conformance.
    private var counterHigh: UInt64 = 0

    public init(digestLength: Int = Self.maximumDigestLength, key: [UInt8] = []) {
        precondition((1...Self.maximumDigestLength).contains(digestLength), "BLAKE2b digests are 1 to 64 bytes")
        precondition(key.count <= Self.maximumKeyLength, "BLAKE2b keys are at most 64 bytes")
        self.digestLength = digestLength
        state = Self.iv
        state[0] ^= Self.sequentialModeParameters ^ (UInt64(key.count) << 8) ^ UInt64(digestLength)
        block = [UInt8](repeating: 0, count: Self.blockSize)
        // A key is hashed as a first block padded with zeros; it counts as 128 bytes of input.
        if !key.isEmpty {
            block.replaceSubrange(0..<key.count, with: key)
            pending = Self.blockSize
        }
    }

    public mutating func update(_ input: some Sequence<UInt8>) {
        update(bytes: Array(input))
    }

    /// Copies whole runs into the block rather than one byte at a time; a generic per-byte
    /// loop cannot be specialized across the module boundary and runs about 50 ns per byte.
    private mutating func update(bytes: [UInt8]) {
        var offset = 0
        while offset < bytes.count {
            if pending == Self.blockSize {
                addToCounter(UInt64(Self.blockSize))
                compress(final: false)
                pending = 0
            }
            let count = min(Self.blockSize - pending, bytes.count - offset)
            block.replaceSubrange(pending..<pending + count, with: bytes[offset..<offset + count])
            pending += count
            offset += count
        }
    }

    /// The digest of everything given to `update` so far; the hasher stays usable.
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

    public static func hash(
        _ message: some Sequence<UInt8>, key: [UInt8] = [], digestLength: Int = Self.maximumDigestLength
    ) -> [UInt8] {
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

    /// The working vector lives in sixteen locals, not an array, so the 96 mixes per block
    /// are register arithmetic with no bounds checks.
    private mutating func compress(final: Bool) {
        for word in 0..<Self.wordsPerBlock {
            var value: UInt64 = 0
            for byte in 0..<8 {
                value |= UInt64(block[word * 8 + byte]) << UInt64(8 * byte)
            }
            words[word] = value
        }
        var v0 = state[0]
        var v1 = state[1]
        var v2 = state[2]
        var v3 = state[3]
        var v4 = state[4]
        var v5 = state[5]
        var v6 = state[6]
        var v7 = state[7]
        var v8 = Self.iv[0]
        var v9 = Self.iv[1]
        var v10 = Self.iv[2]
        var v11 = Self.iv[3]
        var v12 = Self.iv[4] ^ counterLow
        var v13 = Self.iv[5] ^ counterHigh
        var v14 = final ? ~Self.iv[6] : Self.iv[6]
        var v15 = Self.iv[7]
        for round in 0..<Self.rounds {
            let s = Self.sigma[round % Self.sigma.count]
            Self.mix(&v0, &v4, &v8, &v12, words[s[0]], words[s[1]])
            Self.mix(&v1, &v5, &v9, &v13, words[s[2]], words[s[3]])
            Self.mix(&v2, &v6, &v10, &v14, words[s[4]], words[s[5]])
            Self.mix(&v3, &v7, &v11, &v15, words[s[6]], words[s[7]])
            Self.mix(&v0, &v5, &v10, &v15, words[s[8]], words[s[9]])
            Self.mix(&v1, &v6, &v11, &v12, words[s[10]], words[s[11]])
            Self.mix(&v2, &v7, &v8, &v13, words[s[12]], words[s[13]])
            Self.mix(&v3, &v4, &v9, &v14, words[s[14]], words[s[15]])
        }
        state[0] ^= v0 ^ v8
        state[1] ^= v1 ^ v9
        state[2] ^= v2 ^ v10
        state[3] ^= v3 ^ v11
        state[4] ^= v4 ^ v12
        state[5] ^= v5 ^ v13
        state[6] ^= v6 ^ v14
        state[7] ^= v7 ^ v15
    }

    private static func mix(
        _ a: inout UInt64, _ b: inout UInt64, _ c: inout UInt64, _ d: inout UInt64, _ x: UInt64, _ y: UInt64
    ) {
        a = a &+ b &+ x
        d = rotateRight(d ^ a, by: 32)
        c = c &+ d
        b = rotateRight(b ^ c, by: 24)
        a = a &+ b &+ y
        d = rotateRight(d ^ a, by: 16)
        c = c &+ d
        b = rotateRight(b ^ c, by: 63)
    }

    private static func rotateRight(_ value: UInt64, by bits: UInt64) -> UInt64 {
        (value >> bits) | (value << (64 - bits))
    }
}
