//
//  Bech32.swift
//  KeyFormats
//

/// Bech32 encoding (BIP 173), as age writes its keys.
enum Bech32 {
    private static let alphabet = Array("qpzry9x8gf2tvdw0s3jn54khce6mua7l")
    private static let generator: [UInt32] = [0x3b6a_57b2, 0x2650_8e6d, 0x1ea1_19fa, 0x3d42_33dd, 0x2a14_62b3]
    private static let checksumLength = 6

    /// `hrp` must be lower case; the checksum is defined over the lower case string.
    static func encode(hrp: String, bytes: [UInt8]) -> String {
        let values = regroup(bytes)
        let checksum = checksum(hrp: hrp, values: values)
        return hrp + "1" + String((values + checksum).map { alphabet[Int($0)] })
    }

    /// 8-bit bytes as 5-bit values, the last padded with zero bits.
    static func regroup(_ bytes: [UInt8]) -> [UInt8] {
        var values: [UInt8] = []
        var accumulator: UInt32 = 0
        var bits = 0
        for byte in bytes {
            accumulator = accumulator << 8 | UInt32(byte)
            bits += 8
            while bits >= 5 {
                bits -= 5
                values.append(UInt8(accumulator >> UInt32(bits) & 31))
            }
        }
        if bits > 0 { values.append(UInt8(accumulator << UInt32(5 - bits) & 31)) }
        return values
    }

    static func checksum(hrp: String, values: [UInt8]) -> [UInt8] {
        let expanded = hrp.utf8.map { $0 >> 5 } + [0] + hrp.utf8.map { $0 & 31 }
        let polymod = polymod(expanded + values + [UInt8](repeating: 0, count: checksumLength)) ^ 1
        return (0..<checksumLength).map { UInt8(polymod >> UInt32(5 * (checksumLength - 1 - $0)) & 31) }
    }

    private static func polymod(_ values: [UInt8]) -> UInt32 {
        var check: UInt32 = 1
        for value in values {
            let top = check >> 25
            check = (check & 0x1ff_ffff) << 5 ^ UInt32(value)
            for (bit, term) in generator.enumerated() where top >> UInt32(bit) & 1 == 1 {
                check ^= term
            }
        }
        return check
    }
}
