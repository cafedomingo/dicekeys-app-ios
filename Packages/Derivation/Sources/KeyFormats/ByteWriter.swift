//
//  ByteWriter.swift
//  KeyFormats
//

/// Big-endian writer shared by the OpenSSH and OpenPGP encoders.
struct ByteWriter {
    private(set) var bytes: [UInt8] = []

    var count: Int { bytes.count }

    mutating func byte(_ value: UInt8) { bytes.append(value) }

    mutating func uint16(_ value: UInt16) {
        bytes.append(UInt8(value >> 8))
        bytes.append(UInt8(truncatingIfNeeded: value))
    }

    mutating func uint32(_ value: UInt32) {
        for shift in stride(from: 24, through: 0, by: -8) {
            bytes.append(UInt8(truncatingIfNeeded: value >> UInt32(shift)))
        }
    }

    mutating func append(_ more: some Sequence<UInt8>) { bytes.append(contentsOf: more) }

    mutating func sshString(_ value: [UInt8]) {
        uint32(UInt32(value.count))
        append(value)
    }

    mutating func sshString(_ text: String) { sshString(Array(text.utf8)) }

    /// An OpenPGP multiprecision integer: bit length, then the value without leading zero bytes.
    mutating func mpi(_ value: [UInt8]) {
        let leadingZeroBits = value.reduce(into: (bits: 0, done: false)) { count, byte in
            guard !count.done else { return }
            if byte == 0 {
                count.bits += 8
            } else {
                count.bits += byte.leadingZeroBitCount
                count.done = true
            }
        }.bits
        uint16(UInt16(value.count * 8 - leadingZeroBits))
        append(value.dropFirst(leadingZeroBits / 8))
    }
}
