//
//  Armor.swift
//  KeyFormats
//

import Foundation

/// PEM-style armor: 64-column base64 between BEGIN and END lines. With `crc`, OpenPGP's
/// blank line after the header and CRC24 line.
enum Armor {
    static func base64Lines(_ bytes: [UInt8]) -> String {
        let encoded = Data(bytes).base64EncodedString()
        var lines = [Substring]()
        var index = encoded.startIndex
        while index < encoded.endIndex {
            let end = encoded.index(index, offsetBy: 64, limitedBy: encoded.endIndex) ?? encoded.endIndex
            lines.append(encoded[index..<end])
            index = end
        }
        return lines.joined(separator: "\n")
    }

    static func pem(_ label: String, _ bytes: [UInt8], crc: Bool) -> String {
        var text = "-----BEGIN \(label)-----\n"
        if crc { text += "\n" }
        text += base64Lines(bytes) + "\n"
        if crc { text += "=" + Data(crc24(bytes)).base64EncodedString() + "\n" }
        return text + "-----END \(label)-----\n"
    }

    /// RFC 4880 section 6.1.
    static func crc24(_ bytes: [UInt8]) -> [UInt8] {
        var crc: UInt32 = 0xb70_4ce
        for byte in bytes {
            crc ^= UInt32(byte) << 16
            for _ in 0..<8 {
                crc <<= 1
                if crc & 0x100_0000 != 0 { crc ^= 0x186_4cfb }
            }
        }
        return [UInt8(truncatingIfNeeded: crc >> 16), UInt8(truncatingIfNeeded: crc >> 8), UInt8(truncatingIfNeeded: crc)]
    }
}
