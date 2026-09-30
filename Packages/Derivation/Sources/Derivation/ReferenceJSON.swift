//
//  ReferenceJSON.swift
//  Derivation
//

/// The JSON layout the C++ produced through nlohmann's `dump()`: keys in byte order, no
/// whitespace, `/` unescaped, non-ASCII raw. Every derived value's `toJson()` must stay in
/// this layout because it is what other DiceKeys apps display.
enum ReferenceJSON {
    static func object(_ fields: [(key: String, value: String)]) -> String {
        let sorted = fields.sorted { $0.key.utf8.lexicographicallyPrecedes($1.key.utf8) }
        return "{" + sorted.map { "\(quotedJsonString($0.key)):\(quotedJsonString($0.value))" }.joined(separator: ",") + "}"
    }

    /// Password, Secret and SymmetricKey omit an empty recipe; the key pairs always write it.
    static func recipeIfPresent(_ recipe: Recipe) -> [(key: String, value: String)] {
        recipe.json.isEmpty ? [] : [(key: "recipe", value: recipe.json)]
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
