//
//  KeyFormatsComparisonTests.swift
//  DerivationTests
//

import CryptoKit
import Foundation
import Testing
import Derivation

@testable import KeyFormats

@Suite("OpenSSH against the C++")
struct OpenSSHComparisonTests {
    static let signingCases = fixture.cases.filter { $0.type == "SigningKey" }

    @Test("public lines and masked private keys are identical", arguments: signingCases)
    func matchesFixture(vector: Vector) throws {
        let key = try SigningKey.derive(seed: vector.seed, recipe: vector.recipe)
        #expect(OpenSSH.publicKeyLine(key) == vector.openSshPublicKey)
        let recorded = try #require(vector.openSshPemPrivateKey)
        let ours = OpenSSH.privateKeyPEM(key, comment: vector.sshComment ?? "")
        #expect(ours.count == recorded.count)
        #expect(try maskedOpenSshKey(ours) == maskedOpenSshKey(recorded))
    }

    @Test("the check value is deterministic and equals the first four bytes of SHA-256 of the public key")
    func checkValue() throws {
        let key = try SigningKey.derive(seed: fixture.diceKeys[0].seed, recipe: #"{"purpose":"ssh"}"#)
        let bytes = try decodedPem(OpenSSH.privateKeyPEM(key))
        let offset = try privateSectionOffset(bytes)
        let expected = Array(SHA256.hash(data: key.verificationKeyBytes).prefix(4))
        #expect(Array(bytes[offset..<offset + 4]) == expected)
        #expect(Array(bytes[offset + 4..<offset + 8]) == expected)
        #expect(OpenSSH.privateKeyPEM(key) == OpenSSH.privateKeyPEM(key))
    }

    @Test("ssh-keygen reads the private key and derives the same public line")
    func sshKeygen() throws {
        #if os(macOS)
            guard FileManager.default.isExecutableFile(atPath: "/usr/bin/ssh-keygen") else { return }
            let key = try SigningKey.derive(seed: fixture.diceKeys[1].seed, recipe: #"{"purpose":"ssh"}"#)
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: directory) }
            let file = directory.appendingPathComponent("key")
            try OpenSSH.privateKeyPEM(key, comment: "alice@laptop").write(to: file, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/ssh-keygen")
            process.arguments = ["-y", "-f", file.path]
            let pipe = Pipe()
            process.standardOutput = pipe
            try process.run()
            process.waitUntilExit()
            let output = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            #expect(process.terminationStatus == 0)
            // ssh-keygen prints the key's own comment instead of the fixed "DiceKeys".
            #expect(output == OpenSSH.publicKeyLine(key).replacingOccurrences(of: " DiceKeys", with: " alice@laptop"))
        #endif
    }
}

func decodedPem(_ pem: String) throws -> [UInt8] {
    let body = pem.split(separator: "\n").filter { !$0.hasPrefix("-----") && !$0.hasPrefix("=") && !$0.isEmpty }
        .joined()
    return [UInt8](try #require(Data(base64Encoded: body)))
}

/// The binary body of an OpenSSH private key with its two check-int copies zeroed.
func maskedOpenSshKey(_ pem: String) throws -> [UInt8] {
    var bytes = try decodedPem(pem)
    let offset = try privateSectionOffset(bytes)
    for index in offset..<offset + 8 { bytes[index] = 0 }
    return bytes
}

/// Offset of the first `checkint` in an unencrypted `openssh-key-v1` blob.
func privateSectionOffset(_ bytes: [UInt8]) throws -> Int {
    var offset = "openssh-key-v1\0".utf8.count
    func uint32(at index: Int) -> Int { bytes[index..<index + 4].reduce(0) { $0 << 8 | Int($1) } }
    for _ in 0..<3 { offset += 4 + uint32(at: offset) }
    offset += 4
    offset += 4 + uint32(at: offset)
    offset += 4
    return offset
}

@Suite("OpenPGP against the C++")
struct OpenPGPComparisonTests {
    static let signingCases = fixture.cases.filter { $0.type == "SigningKey" }

    @Test("everything but the framing, the key flags and the signature is identical", arguments: signingCases)
    func matchesFixtureByContent(vector: Vector) throws {
        let key = try SigningKey.derive(seed: vector.seed, recipe: vector.recipe)
        let ours = try OpenPGPWalker(
            armored: OpenPGP.secretKeyBlock(key, userId: vector.pgpUserId ?? "", timestamp: vector.pgpTimestamp ?? 0))
        let theirs = try OpenPGPWalker(armored: try #require(vector.openPgpPemFormatSecretKey))
        #expect(try ours.secretKey == theirs.secretKey)
        #expect(try ours.userId == theirs.userId)
        let (mine, reference) = (try ours.signature, try theirs.signature)
        #expect(mine.version == reference.version && mine.signatureType == reference.signatureType)
        #expect(
            mine.publicKeyAlgorithm == reference.publicKeyAlgorithm && mine.hashAlgorithm == reference.hashAlgorithm)
        #expect(mine.unhashed == reference.unhashed)
        let mineFlagsFixed = mine.hashed.map {
            $0.type == 0x1b ? OpenPGPWalker.Subpacket(type: 0x1b, body: [0x01]) : $0
        }
        #expect(mineFlagsFixed == reference.hashed)
        #expect(mine.hashed.first { $0.type == 0x1b }?.body == [0x03])
        #expect(ours.hadBlankLine && !theirs.hadBlankLine)
        #expect(ours.crc == Armor.crc24(ours.bytes))
        #expect(theirs.crc == nil)
    }

    @Test("the self-signature verifies and the hash prefix matches", arguments: signingCases.prefix(4))
    func signatureVerifies(vector: Vector) throws {
        let key = try SigningKey.derive(seed: vector.seed, recipe: vector.recipe)
        let block = OpenPGP.secretKeyBlock(key, userId: vector.pgpUserId ?? "", timestamp: vector.pgpTimestamp ?? 0)
        let walker = try OpenPGPWalker(armored: block)
        let signature = try walker.signature
        let publicBody = try OpenPGP.publicKeyPacketBody(from: walker.secretKey.body)
        var preimage = ByteWriter()
        preimage.byte(0x99)
        preimage.uint16(UInt16(publicBody.count))
        preimage.append(publicBody)
        preimage.byte(0xb4)
        preimage.uint32(UInt32(try walker.userId.count))
        preimage.append(try walker.userId)
        preimage.append(signature.hashedRegion)
        preimage.byte(0x04)
        preimage.byte(0xff)
        preimage.uint32(UInt32(signature.hashedRegion.count))
        let digest = Array(SHA256.hash(data: preimage.bytes))
        #expect(signature.hashPrefix == Array(digest.prefix(2)))
        let r = [UInt8](repeating: 0, count: 32 - (signature.r.count - 2)) + signature.r.dropFirst(2)
        let s = [UInt8](repeating: 0, count: 32 - (signature.s.count - 2)) + signature.s.dropFirst(2)
        let publicKey = try Curve25519.Signing.PublicKey(rawRepresentation: key.verificationKeyBytes)
        #expect(publicKey.isValidSignature(r + s, for: digest))
    }

    @Test("two exports differ only in the signature")
    func onlyTheSignatureVaries() throws {
        let key = try SigningKey.derive(seed: fixture.diceKeys[2].seed, recipe: #"{"purpose":"pgp"}"#)
        let first = try OpenPGPWalker(armored: OpenPGP.secretKeyBlock(key))
        let second = try OpenPGPWalker(armored: OpenPGP.secretKeyBlock(key))
        #expect(try first.secretKey == second.secretKey)
        #expect(try first.userId == second.userId)
        #expect(try first.signature.hashed == second.signature.hashed)
        #expect(try first.signature.hashPrefix == second.signature.hashPrefix)
    }

    @Test("a long user ID gets a two-byte packet length")
    func longUserId() throws {
        let key = try SigningKey.derive(seed: fixture.diceKeys[3].seed, recipe: #"{"purpose":"pgp"}"#)
        let userId = String(repeating: "x", count: 300)
        let walker = try OpenPGPWalker(armored: OpenPGP.secretKeyBlock(key, userId: userId))
        #expect(try walker.userId == Array(userId.utf8))
        #expect(walker.packets.count == 3)
    }

    @Test("the CRC24 matches the standard check value")
    func crc24() {
        #expect(Armor.crc24([]) == [0xb7, 0x04, 0xce])
        #expect(Armor.crc24(Array("Hello".utf8)) != [0xb7, 0x04, 0xce])
        #expect(Armor.crc24(Array("123456789".utf8)) == [0x21, 0xcf, 0x02])
    }

    @Test("packets and subpackets switch length encoding at the RFC 4880 boundaries")
    func framingLengthBranches() {
        // 0xb4 is 0x80 | 13 << 2; length type 2 (a four-byte length) makes 0xb6.
        let long = OpenPGP.packet(tag: 13, body: [UInt8](repeating: 0x41, count: 65_536))
        #expect(Array(long.prefix(5)) == [0xb6, 0x00, 0x01, 0x00, 0x00])
        #expect(long.count == 5 + 65_536)
        // Subpacket lengths include the type byte, so 190 body bytes give 191.
        let lengths: [(body: Int, header: [UInt8])] = [
            (190, [191, 0x14]),
            (191, [192, 0, 0x14]),
            (8382, [223, 255, 0x14]),
            (8383, [255, 0, 0, 0x20, 0xc0, 0x14])
        ]
        for (count, header) in lengths {
            let framed = OpenPGP.subpacket(type: 0x14, body: [UInt8](repeating: 0x41, count: count))
            #expect(Array(framed.prefix(header.count)) == header)
            #expect(framed.count == header.count + count)
        }
    }
}
