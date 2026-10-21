//
//  ByteWriter.swift
//  KeyFormats
//

/// Big-endian writer for the OpenSSH encoder.
struct ByteWriter {
    private(set) var bytes: [UInt8] = []

    var count: Int { bytes.count }

    mutating func byte(_ value: UInt8) { bytes.append(value) }

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
}
