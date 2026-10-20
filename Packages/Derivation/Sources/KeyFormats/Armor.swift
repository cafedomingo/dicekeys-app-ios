//
//  Armor.swift
//  KeyFormats
//

import Foundation

/// PEM-style armor: 64-column base64 between BEGIN and END lines.
enum Armor {
    private static let lineLength = 64

    private static func base64Lines(_ bytes: [UInt8]) -> String {
        let encoded = Data(bytes).base64EncodedString()
        var lines = [Substring]()
        var index = encoded.startIndex
        while index < encoded.endIndex {
            let end = encoded.index(index, offsetBy: lineLength, limitedBy: encoded.endIndex) ?? encoded.endIndex
            lines.append(encoded[index..<end])
            index = end
        }
        return lines.joined(separator: "\n")
    }

    static func pem(_ label: String, _ bytes: [UInt8]) -> String {
        "-----BEGIN \(label)-----\n" + base64Lines(bytes) + "\n-----END \(label)-----\n"
    }
}
