//
//  OpenPGP.swift
//  KeyFormats
//

import CryptoKit
import Derivation
import Foundation

/// A transferable secret key (RFC 4880): v4 secret key, user ID and self-signature packets
/// in old-format framing, with legacy EdDSA algorithm 22 and the Ed25519 OID.
public enum OpenPGP {
    static let version: UInt8 = 4
    static let eddsa: UInt8 = 22
    static let sha256: UInt8 = 8
    static let ed25519OID: [UInt8] = [0x2b, 0x06, 0x01, 0x04, 0x01, 0xda, 0x47, 0x0f, 0x01]

    /// Timestamp 0 keeps the fingerprint stable, because the v4 fingerprint hashes the
    /// creation time. CryptoKit randomizes the signature, so exports of one key differ only
    /// in the signature MPIs, their bit lengths and, if a leading zero drops, the length octets.
    public static func secretKeyBlock(_ key: Derivation.SigningKey, userId: String = "", timestamp: UInt32 = 0) -> String {
        let seed = Array(key.signingKeyBytes.prefix(32))
        let publicKey = Array(key.verificationKeyBytes)
        let publicBody = publicKeyPacketBody(publicKey: publicKey, timestamp: timestamp)
        var secretBody = ByteWriter()
        secretBody.append(publicBody)
        secretBody.byte(0)                       // S2K usage: unprotected
        var secretMPI = ByteWriter()
        secretMPI.mpi(seed)
        secretBody.append(secretMPI.bytes)
        secretBody.uint16(secretMPI.bytes.reduce(UInt16(0)) { $0 &+ UInt16($1) })
        let userIdBody = Array(userId.utf8)
        var block = ByteWriter()
        block.append(packet(tag: 5, body: secretBody.bytes))
        block.append(packet(tag: 13, body: userIdBody))
        block.append(packet(tag: 2, body: signaturePacketBody(seed: seed, publicBody: publicBody, userIdBody: userIdBody, timestamp: timestamp)))
        return Armor.pem("PGP PRIVATE KEY BLOCK", block.bytes, crc: true)
    }

    /// The public point is an MPI with the 0x40 prefix of a compressed EdDSA point.
    static func publicKeyPacketBody(publicKey: [UInt8], timestamp: UInt32) -> [UInt8] {
        var body = ByteWriter()
        body.byte(version)
        body.uint32(timestamp)
        body.byte(eddsa)
        body.byte(UInt8(ed25519OID.count))
        body.append(ed25519OID)
        body.mpi([0x40] + publicKey)
        return body.bytes
    }

    /// The public key packet body is a prefix of the secret key body; throws if it is too short.
    public static func publicKeyPacketBody(from secretKeyBody: [UInt8]) throws -> [UInt8] {
        let fixed = 1 + 4 + 1 + 1 + ed25519OID.count
        guard secretKeyBody.count > fixed + 2 else { throw Error.malformed }
        let bits = Int(secretKeyBody[fixed]) << 8 | Int(secretKeyBody[fixed + 1])
        return Array(secretKeyBody.prefix(fixed + 2 + (bits + 7) / 8))
    }

    public enum Error: Swift.Error { case malformed }

    /// The framing that starts both the fingerprint and the self-signature preimage.
    private static func keyHashPreimage(publicBody: [UInt8]) -> ByteWriter {
        var preimage = ByteWriter()
        preimage.byte(0x99)
        preimage.uint16(UInt16(publicBody.count))
        preimage.append(publicBody)
        return preimage
    }

    static func fingerprint(publicBody: [UInt8]) -> [UInt8] {
        Array(Insecure.SHA1.hash(data: keyHashPreimage(publicBody: publicBody).bytes))
    }

    private static func signaturePacketBody(seed: [UInt8], publicBody: [UInt8], userIdBody: [UInt8], timestamp: UInt32) -> [UInt8] {
        let fingerprint = fingerprint(publicBody: publicBody)
        var hashedSubpackets = ByteWriter()
        hashedSubpackets.append(subpacket(type: 0x21, body: [version] + fingerprint))       // issuer fingerprint
        var creation = ByteWriter()
        creation.uint32(timestamp)
        hashedSubpackets.append(subpacket(type: 0x02, body: creation.bytes))                 // creation time
        hashedSubpackets.append(subpacket(type: 0x1b, body: [0x03]))                        // key flags: certify, sign
        hashedSubpackets.append(subpacket(type: 0x0b, body: [0x09, 0x08, 0x07, 0x02]))      // preferred symmetric
        hashedSubpackets.append(subpacket(type: 0x15, body: [0x0a, 0x09, 0x08, 0x0b, 0x02])) // preferred hash
        hashedSubpackets.append(subpacket(type: 0x16, body: [0x02, 0x03, 0x01]))            // preferred compression
        hashedSubpackets.append(subpacket(type: 0x1e, body: [0x01]))                        // features: MDC
        hashedSubpackets.append(subpacket(type: 0x17, body: [0x80]))                        // key server: no-modify

        var hashedRegion = ByteWriter()
        hashedRegion.byte(version)
        hashedRegion.byte(0x13)          // positive certification of a user ID and public key
        hashedRegion.byte(eddsa)
        hashedRegion.byte(sha256)
        hashedRegion.uint16(UInt16(hashedSubpackets.count))
        hashedRegion.append(hashedSubpackets.bytes)

        var preimage = keyHashPreimage(publicBody: publicBody)
        preimage.byte(0xb4)
        preimage.uint32(UInt32(userIdBody.count))
        preimage.append(userIdBody)
        preimage.append(hashedRegion.bytes)
        preimage.byte(version)
        preimage.byte(0xff)
        preimage.uint32(UInt32(hashedRegion.count))
        let digest = Array(SHA256.hash(data: preimage.bytes))

        // A 32-byte seed always works, so failure means a broken framework.
        let signature: [UInt8]
        do {
            signature = Array(try Curve25519.Signing.PrivateKey(rawRepresentation: seed).signature(for: digest))
        } catch {
            preconditionFailure("CryptoKit refused a 32-byte Ed25519 seed: \(error)")
        }

        var body = ByteWriter()
        body.append(hashedRegion.bytes)
        let issuer = subpacket(type: 0x10, body: Array(fingerprint.suffix(8)))
        body.uint16(UInt16(issuer.count))
        body.append(issuer)
        body.append(digest.prefix(2))
        body.mpi(Array(signature[0..<32]))
        body.mpi(Array(signature[32..<64]))
        return body.bytes
    }

    /// Old-format framing: tag byte 0x80 | tag << 2 | length type, then a 1, 2 or 4 byte length.
    static func packet(tag: UInt8, body: [UInt8]) -> [UInt8] {
        var out = ByteWriter()
        switch body.count {
        case ..<256:
            out.byte(0x80 | tag << 2)
            out.byte(UInt8(body.count))
        case ..<65536:
            out.byte(0x80 | tag << 2 | 1)
            out.uint16(UInt16(body.count))
        default:
            out.byte(0x80 | tag << 2 | 2)
            out.uint32(UInt32(body.count))
        }
        out.append(body)
        return out.bytes
    }

    /// Subpacket framing (RFC 4880 section 5.2.3.1): the length covers the type byte.
    static func subpacket(type: UInt8, body: [UInt8]) -> [UInt8] {
        var out = ByteWriter()
        let length = body.count + 1
        switch length {
        case ..<192:
            out.byte(UInt8(length))
        case ..<8384:
            out.byte(UInt8((length - 192) >> 8 + 192))
            out.byte(UInt8(truncatingIfNeeded: length - 192))
        default:
            out.byte(255)
            out.uint32(UInt32(length))
        }
        out.byte(type)
        out.append(body)
        return out.bytes
    }
}
