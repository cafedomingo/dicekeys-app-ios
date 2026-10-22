//
//  KeyFileTests.swift
//  DiceKeyVaultTests
//

import Derivation
import KeyFormats
import Testing

@testable import DiceKeyVault

struct KeyFileTests {
    private func filename(_ kind: KeyKind, _ name: String) throws -> String {
        let recipe = try KeyRecipe(kind: kind, name: name)
        return KeyFile(key: DerivedKey.derive(seed: DiceKey.example.seed, recipe: recipe)).filename
    }

    @Test(
        "a file is named for its tool and the key's letters and digits",
        arguments: [
            (KeyKind.ssh, "github", "id_ed25519_github"),
            (.ssh, "homelab host", "id_ed25519_homelab-host"),
            (.ssh, "👩‍💻 laptop", "id_ed25519_laptop"),
            (.ssh, "café / nas", "id_ed25519_café-nas"),
            (.ssh, "🧨", "id_ed25519"),
            (.age, "backups 2026", "age-backups-2026.txt"),
            (.age, "🇺🇸", "age.txt")
        ])
    func names(kind: KeyKind, name: String, expected: String) throws {
        #expect(try filename(kind, name) == expected)
    }
}
