//
//  ReferenceJSON.swift
//  Derivation
//

/// Compact JSON as nlohmann's `dump()` writes it: keys in byte order, `/` unescaped,
/// non-ASCII raw. Other DiceKeys apps display this layout, so it cannot change.
enum ReferenceJSON {
    static let recipeKey = "recipe"

    static func object(_ fields: [(key: String, value: String)]) -> String {
        let sorted = fields.sorted { $0.key.utf8.lexicographicallyPrecedes($1.key.utf8) }
        return "{" + sorted.map { "\(quotedJsonString($0.key)):\(quotedJsonString($0.value))" }.joined(separator: ",")
            + "}"
    }

    /// Password, Secret and SymmetricKey omit an empty recipe; the key pairs always write it.
    static func recipeIfPresent(_ recipe: Recipe) -> [(key: String, value: String)] {
        recipe.json.isEmpty ? [] : [(key: recipeKey, value: recipe.json)]
    }

    static func hex(_ bytes: some Sequence<UInt8>) -> String {
        let digits = Array("0123456789abcdef".utf8)
        var out = [UInt8]()
        for byte in bytes {
            out.append(digits[Int(byte >> 4)])
            out.append(digits[Int(byte & 0x0f)])
        }
        return String(decoding: out, as: UTF8.self)
    }
}
