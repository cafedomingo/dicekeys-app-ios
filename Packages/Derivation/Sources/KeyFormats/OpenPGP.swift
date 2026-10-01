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

    // Packet tags, RFC 4880 section 4.3.
    private static let signaturePacketTag: UInt8 = 2
    private static let secretKeyPacketTag: UInt8 = 5
    private static let userIdPacketTag: UInt8 = 13

    // Signature subpacket types, RFC 4880 section 5.2.3.1 (issuer fingerprint is RFC 4880bis).
    private static let creationTimeSubpacket: UInt8 = 0x02
    private static let preferredSymmetricSubpacket: UInt8 = 0x0b
    private static let issuerSubpacket: UInt8 = 0x10
    private static let preferredHashSubpacket: UInt8 = 0x15
    private static let preferredCompressionSubpacket: UInt8 = 0x16
    private static let keyServerPreferencesSubpacket: UInt8 = 0x17
    private static let keyFlagsSubpacket: UInt8 = 0x1b
    private static let featuresSubpacket: UInt8 = 0x1e
    private static let issuerFingerprintSubpacket: UInt8 = 0x21

    /// Signature type 0x13, positive certification of a user ID and public key (RFC 4880 section 5.2.1).
    private static let positiveCertification: UInt8 = 0x13
    /// Public-key packet header as hashed: 0x99 is old-format tag 6 with a two-octet length
    /// (RFC 4880 section 12.2).
    private static let publicKeyHashHeader: UInt8 = 0x99
    /// User ID header as hashed in a certification: 0xb4 is tag 13, followed by a four-octet length (section 5.2.4).
    private static let userIdHashHeader: UInt8 = 0xb4
    /// The octet between the version and the length in a v4 signature's hash trailer (section 5.2.4).
    private static let signatureTrailerMarker: UInt8 = 0xff
    /// An EdDSA point is stored with this prefix byte for the compressed form.
    private static let compressedPointPrefix: UInt8 = 0x40
    /// The key ID is the low-order 64 bits of the fingerprint.
    private static let keyIdLength = 8
    /// The signature packet carries the first two octets of the signed hash as a quick check.
    private static let hashCheckLength = 2

    /// Old-format packet header: bit 7 is always set (RFC 4880 section 4.2).
    private static let oldFormatPacketBit: UInt8 = 0x80
    /// Subpacket lengths below 192 take one octet, below 8384 two, and 255 introduces four more
    /// (RFC 4880 section 5.2.3.1).
    private static let subpacketOneOctetLimit = 192
    private static let subpacketTwoOctetLimit = 8384
    private static let subpacketFourOctetMarker: UInt8 = 255

    /// Timestamp 0 keeps the fingerprint stable, because the v4 fingerprint hashes the
    /// creation time. CryptoKit randomizes the signature, so exports of one key differ only
    /// in the signature MPIs, their bit lengths and, if a leading zero drops, the length octets.
    public static func secretKeyBlock(_ key: Derivation.SigningKey, userId: String = "", timestamp: UInt32 = 0)
        -> String
    {
        let seed = Array(key.signingKeyBytes.prefix(Derivation.SigningKey.seedLength))
        let publicKey = Array(key.verificationKeyBytes)
        let publicBody = publicKeyPacketBody(publicKey: publicKey, timestamp: timestamp)
        var secretBody = ByteWriter()
        secretBody.append(publicBody)
        secretBody.byte(0)  // S2K usage: unprotected
        var secretMPI = ByteWriter()
        secretMPI.mpi(seed)
        secretBody.append(secretMPI.bytes)
        secretBody.uint16(secretMPI.bytes.reduce(UInt16(0)) { $0 &+ UInt16($1) })
        let userIdBody = Array(userId.utf8)
        var block = ByteWriter()
        block.append(packet(tag: secretKeyPacketTag, body: secretBody.bytes))
        block.append(packet(tag: userIdPacketTag, body: userIdBody))
        block.append(
            packet(
                tag: signaturePacketTag,
                body: signaturePacketBody(
                    seed: seed, publicBody: publicBody, userIdBody: userIdBody, timestamp: timestamp)))
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
        body.mpi([compressedPointPrefix] + publicKey)
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
        preimage.byte(publicKeyHashHeader)
        preimage.uint16(UInt16(publicBody.count))
        preimage.append(publicBody)
        return preimage
    }

    static func fingerprint(publicBody: [UInt8]) -> [UInt8] {
        Array(Insecure.SHA1.hash(data: keyHashPreimage(publicBody: publicBody).bytes))
    }

    private static func signaturePacketBody(seed: [UInt8], publicBody: [UInt8], userIdBody: [UInt8], timestamp: UInt32)
        -> [UInt8]
    {
        let fingerprint = fingerprint(publicBody: publicBody)
        var hashedSubpackets = ByteWriter()
        hashedSubpackets.append(subpacket(type: issuerFingerprintSubpacket, body: [version] + fingerprint))
        var creation = ByteWriter()
        creation.uint32(timestamp)
        hashedSubpackets.append(subpacket(type: creationTimeSubpacket, body: creation.bytes))
        hashedSubpackets.append(subpacket(type: keyFlagsSubpacket, body: [0x03]))  // certify, sign
        hashedSubpackets.append(subpacket(type: preferredSymmetricSubpacket, body: [0x09, 0x08, 0x07, 0x02]))
        hashedSubpackets.append(subpacket(type: preferredHashSubpacket, body: [0x0a, 0x09, 0x08, 0x0b, 0x02]))
        hashedSubpackets.append(subpacket(type: preferredCompressionSubpacket, body: [0x02, 0x03, 0x01]))
        hashedSubpackets.append(subpacket(type: featuresSubpacket, body: [0x01]))  // MDC
        hashedSubpackets.append(subpacket(type: keyServerPreferencesSubpacket, body: [0x80]))  // no-modify

        var hashedRegion = ByteWriter()
        hashedRegion.byte(version)
        hashedRegion.byte(positiveCertification)
        hashedRegion.byte(eddsa)
        hashedRegion.byte(sha256)
        hashedRegion.uint16(UInt16(hashedSubpackets.count))
        hashedRegion.append(hashedSubpackets.bytes)

        var preimage = keyHashPreimage(publicBody: publicBody)
        preimage.byte(userIdHashHeader)
        preimage.uint32(UInt32(userIdBody.count))
        preimage.append(userIdBody)
        preimage.append(hashedRegion.bytes)
        preimage.byte(version)
        preimage.byte(signatureTrailerMarker)
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
        let issuer = subpacket(type: issuerSubpacket, body: Array(fingerprint.suffix(keyIdLength)))
        body.uint16(UInt16(issuer.count))
        body.append(issuer)
        body.append(digest.prefix(hashCheckLength))
        body.mpi(Array(signature[0..<32]))
        body.mpi(Array(signature[32..<64]))
        return body.bytes
    }

    /// Old-format framing: tag byte 0x80 | tag << 2 | length type, then a 1, 2 or 4 byte length.
    static func packet(tag: UInt8, body: [UInt8]) -> [UInt8] {
        var out = ByteWriter()
        switch body.count {
        case ..<256:
            out.byte(oldFormatPacketBit | tag << 2)
            out.byte(UInt8(body.count))
        case ..<65536:
            out.byte(oldFormatPacketBit | tag << 2 | 1)
            out.uint16(UInt16(body.count))
        default:
            out.byte(oldFormatPacketBit | tag << 2 | 2)
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
        case ..<subpacketOneOctetLimit:
            out.byte(UInt8(length))
        case ..<subpacketTwoOctetLimit:
            out.byte(UInt8((length - subpacketOneOctetLimit) >> 8 + subpacketOneOctetLimit))
            out.byte(UInt8(truncatingIfNeeded: length - subpacketOneOctetLimit))
        default:
            out.byte(subpacketFourOctetMarker)
            out.uint32(UInt32(length))
        }
        out.byte(type)
        out.append(body)
        return out.bytes
    }
}
