//
//  KeyFormatsComparisonTests.swift
//  DerivationTests
//

import CryptoKit
import Derivation
import Foundation
import Testing

@testable import KeyFormats

@Suite("OpenSSH against the C++")
struct OpenSSHComparisonTests {
    static let signingCases = fixture.cases.filter { $0.type == "SigningKey" }
    /// What the reference implementation's public lines end in.
    static let referenceComment = "DiceKeys"

    @Test("public lines and masked private keys are identical", arguments: signingCases)
    func matchesFixture(vector: Vector) throws {
        let key = try SigningKey.derive(seed: vector.seed, recipe: vector.recipe)
        #expect(OpenSSH.publicKeyLine(key, comment: Self.referenceComment) == vector.openSshPublicKey)
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
            let comment = "alice@laptop"
            try OpenSSH.privateKeyPEM(key, comment: comment).write(to: file, atomically: true, encoding: .utf8)
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
            #expect(output == OpenSSH.publicKeyLine(key, comment: comment))
        #endif
    }
}

func decodedPem(_ pem: String) throws -> [UInt8] {
    let body = pem.split(separator: "\n").filter { !$0.hasPrefix("-----") && !$0.isEmpty }
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
