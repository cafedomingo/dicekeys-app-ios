//
//  Native.swift
//  SeededCrypto
//
//  Thin, safe plumbing over the C ABI in SeededCryptoNative. Everything the
//  library returns is malloc'd by C++ and freed here, in one place.
//

import Foundation
import SeededCryptoNative

/// An error reported by the seeded-crypto library (invalid recipe JSON, bad key
/// length, failed cryptographic verification, ...).
public struct SeededCryptoError: Error, LocalizedError, Sendable, Hashable {
    public let message: String

    public init(message: String) {
        self.message = message
    }

    public var errorDescription: String? { message }
}

typealias CStringOut = UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>
typealias BytesOut = UnsafeMutablePointer<dkc_bytes>

enum Native {
    /// Runs a native call that writes a malloc'd UTF-8 string into its first pointer
    /// and an optional error message into its second.
    static func string(_ call: (CStringOut, CStringOut) -> Int32) throws -> String {
        var out: UnsafeMutablePointer<CChar>? = nil
        var error: UnsafeMutablePointer<CChar>? = nil
        let ok = call(&out, &error)
        defer {
            dkc_free(out)
            dkc_free(error)
        }
        guard ok == 1, let out else {
            throw SeededCryptoError(message: error.map { String(cString: $0) } ?? "Unknown SeededCrypto error")
        }
        return String(cString: out)
    }

    /// Runs a native call that writes malloc'd bytes into its first pointer and an
    /// optional error message into its second.
    static func bytes(_ call: (BytesOut, CStringOut) -> Int32) throws -> Data {
        var out = dkc_bytes(data: nil, length: 0)
        var error: UnsafeMutablePointer<CChar>? = nil
        let ok = call(&out, &error)
        defer {
            dkc_bytes_free(out)
            dkc_free(error)
        }
        guard ok == 1, let data = out.data else {
            throw SeededCryptoError(message: error.map { String(cString: $0) } ?? "Unknown SeededCrypto error")
        }
        return Data(bytes: data, count: out.length)
    }

    /// Runs a native call that only reports success/failure plus a flag.
    static func flag(_ call: (UnsafeMutablePointer<Int32>, CStringOut) -> Int32) throws -> Bool {
        var flag: Int32 = 0
        var error: UnsafeMutablePointer<CChar>? = nil
        let ok = call(&flag, &error)
        defer { dkc_free(error) }
        guard ok == 1 else {
            throw SeededCryptoError(message: error.map { String(cString: $0) } ?? "Unknown SeededCrypto error")
        }
        return flag == 1
    }

    /// Gives a native call a stable pointer to `data`'s bytes for its duration.
    static func withBytes<T>(_ data: Data, _ body: (UnsafePointer<UInt8>?, Int) throws -> T) rethrows -> T {
        try data.withUnsafeBytes { raw in
            try body(raw.baseAddress?.assumingMemoryBound(to: UInt8.self), raw.count)
        }
    }

    static func decode<T: Decodable>(_ type: T.Type, from json: String) throws -> T {
        do {
            return try JSONDecoder().decode(type, from: Data(json.utf8))
        } catch {
            throw SeededCryptoError(message: "Could not decode \(T.self) from native JSON: \(error.localizedDescription)")
        }
    }

    /// The version of the vendored libsodium, for diagnostics screens.
    static var sodiumVersion: String { String(cString: dkc_sodium_version()) }
}

extension Data {
    /// Decodes a lower- or upper-case hex string; returns nil on malformed input.
    init?(hexString: String) {
        let chars = Array(hexString.utf8)
        guard chars.count % 2 == 0 else { return nil }
        var bytes = [UInt8]()
        bytes.reserveCapacity(chars.count / 2)
        var index = 0
        while index < chars.count {
            guard let high = Data.nibble(chars[index]), let low = Data.nibble(chars[index + 1]) else { return nil }
            bytes.append(high << 4 | low)
            index += 2
        }
        self.init(bytes)
    }

    private static func nibble(_ c: UInt8) -> UInt8? {
        switch c {
        case UInt8(ascii: "0")...UInt8(ascii: "9"): return c - UInt8(ascii: "0")
        case UInt8(ascii: "a")...UInt8(ascii: "f"): return c - UInt8(ascii: "a") + 10
        case UInt8(ascii: "A")...UInt8(ascii: "F"): return c - UInt8(ascii: "A") + 10
        default: return nil
        }
    }

    /// Lower-case hex, matching what the C++ library emits.
    public var hexString: String {
        map { String(format: "%02x", $0) }.joined()
    }

    /// Decodes a hex field from native JSON, failing loudly if the library ever emits something else.
    static func fromNativeHex(_ hex: String, field: String) throws -> Data {
        guard let data = Data(hexString: hex) else {
            throw SeededCryptoError(message: "Native JSON field \(field) is not hex")
        }
        return data
    }
}
