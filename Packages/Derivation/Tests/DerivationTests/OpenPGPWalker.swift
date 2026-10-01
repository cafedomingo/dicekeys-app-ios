//
//  OpenPGPWalker.swift
//  DerivationTests
//

import Foundation
import Testing

/// Reads enough of RFC 4880 to compare secret key blocks by content. It accepts the recorded
/// export's one-byte lengths and missing CRC as well as the encoder's.
struct OpenPGPWalker {
    struct SecretKeyPacket: Equatable {
        var version: UInt8
        var timestamp: UInt32
        var algorithm: UInt8
        var oid: [UInt8]
        var publicKeyMPI: [UInt8]      // bit length prefix included
        var s2kUsage: UInt8
        var secretKeyMPI: [UInt8]
        var checksum: UInt16
        var body: [UInt8]
    }

    struct Subpacket: Equatable {
        var type: UInt8
        var body: [UInt8]
    }

    struct SignaturePacket: Equatable {
        var version: UInt8
        var signatureType: UInt8
        var publicKeyAlgorithm: UInt8
        var hashAlgorithm: UInt8
        var hashed: [Subpacket]
        var unhashed: [Subpacket]
        var hashPrefix: [UInt8]
        var r: [UInt8]                 // bit length prefix included
        var s: [UInt8]
        var hashedRegion: [UInt8]      // version through the hashed subpackets, for the preimage
    }

    let packets: [(tag: UInt8, body: [UInt8])]
    let hadBlankLine: Bool
    let crc: [UInt8]?
    let bytes: [UInt8]

    init(armored: String) throws {
        let lines = armored.split(separator: "\n", omittingEmptySubsequences: false)
        #expect(lines.first == "-----BEGIN PGP PRIVATE KEY BLOCK-----")
        hadBlankLine = lines.count > 1 && lines[1].isEmpty
        var body = ""
        var crc: [UInt8]?
        for line in lines.dropFirst() {
            if line.hasPrefix("-----END") { break }
            if line.isEmpty { continue }
            if line.hasPrefix("=") { crc = [UInt8](try #require(Data(base64Encoded: String(line.dropFirst())))); continue }
            body += line
        }
        bytes = [UInt8](try #require(Data(base64Encoded: body)))
        self.crc = crc
        var packets = [(tag: UInt8, body: [UInt8])]()
        var index = 0
        while index < bytes.count {
            let header = bytes[index]
            #expect(header & 0xc0 == 0x80, "old-format packet header")
            let tag = (header >> 2) & 0x0f
            let lengthBytes = [1, 2, 4][Int(header & 0x03)]
            var length = 0
            for offset in 1...lengthBytes { length = length << 8 | Int(bytes[index + offset]) }
            let start = index + 1 + lengthBytes
            packets.append((tag, Array(bytes[start..<start + length])))
            index = start + length
        }
        self.packets = packets
    }

    var secretKey: SecretKeyPacket {
        get throws {
            let body = try #require(packets.first { $0.tag == 5 }?.body)
            var reader = Reader(body)
            let version = reader.byte()
            let timestamp = reader.uint32()
            let algorithm = reader.byte()
            let oid = reader.take(Int(reader.byte()))
            let publicKeyMPI = reader.mpi()
            let s2kUsage = reader.byte()
            let secretKeyMPI = reader.mpi()
            let checksum = reader.uint16()
            #expect(reader.atEnd)
            return SecretKeyPacket(version: version, timestamp: timestamp, algorithm: algorithm, oid: oid, publicKeyMPI: publicKeyMPI, s2kUsage: s2kUsage, secretKeyMPI: secretKeyMPI, checksum: checksum, body: body)
        }
    }

    var userId: [UInt8] {
        get throws { try #require(packets.first { $0.tag == 13 }?.body) }
    }

    var signature: SignaturePacket {
        get throws {
            let body = try #require(packets.first { $0.tag == 2 }?.body)
            var reader = Reader(body)
            let version = reader.byte()
            let signatureType = reader.byte()
            let publicKeyAlgorithm = reader.byte()
            let hashAlgorithm = reader.byte()
            let hashedLength = Int(reader.uint16())
            let hashedEnd = reader.offset + hashedLength
            let hashed = try reader.subpackets(until: hashedEnd)
            let hashedRegion = Array(body[0..<hashedEnd])
            let unhashedLength = Int(reader.uint16())
            let unhashed = try reader.subpackets(until: reader.offset + unhashedLength)
            let hashPrefix = reader.take(2)
            let r = reader.mpi()
            let s = reader.mpi()
            #expect(reader.atEnd)
            return SignaturePacket(version: version, signatureType: signatureType, publicKeyAlgorithm: publicKeyAlgorithm, hashAlgorithm: hashAlgorithm, hashed: hashed, unhashed: unhashed, hashPrefix: hashPrefix, r: r, s: s, hashedRegion: hashedRegion)
        }
    }

    private struct Reader {
        let bytes: [UInt8]
        var offset = 0
        init(_ bytes: [UInt8]) { self.bytes = bytes }
        var atEnd: Bool { offset == bytes.count }
        mutating func byte() -> UInt8 { defer { offset += 1 }; return bytes[offset] }
        mutating func uint16() -> UInt16 { UInt16(byte()) << 8 | UInt16(byte()) }
        mutating func uint32() -> UInt32 { UInt32(uint16()) << 16 | UInt32(uint16()) }
        mutating func take(_ count: Int) -> [UInt8] { defer { offset += count }; return Array(bytes[offset..<offset + count]) }
        mutating func mpi() -> [UInt8] {
            let bits = Int(uint16())
            let count = (bits + 7) / 8
            return [UInt8(bits >> 8), UInt8(bits & 0xff)] + take(count)
        }
        mutating func subpackets(until end: Int) throws -> [Subpacket] {
            var result = [Subpacket]()
            while offset < end {
                let first = Int(byte())
                let length: Int
                if first < 192 {
                    length = first
                } else if first < 255 {
                    length = (first - 192) << 8 + Int(byte()) + 192
                } else {
                    length = Int(uint32())
                }
                let type = byte()
                result.append(Subpacket(type: type, body: take(length - 1)))
            }
            #expect(offset == end)
            return result
        }
    }
}
