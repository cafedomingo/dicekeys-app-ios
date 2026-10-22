//
//  KeyFileTests.swift
//  DiceKeyVaultTests
//

import Derivation
import Foundation
import KeyFormats
import Testing

@testable import DiceKeyVault

struct KeyFileTests {
    private func file(_ kind: KeyKind, _ name: String, postQuantum: Bool = false) throws -> KeyFile {
        let key = DerivedKey.derive(seed: DiceKey.example.seed, recipe: try KeyRecipe(kind: kind, name: name))
        guard kind == .age else { return KeyFile(ssh: key) }
        let identity = try #require(postQuantum ? key.postQuantum?.identity : key.secret)
        let recipient = try #require(postQuantum ? key.postQuantum?.recipient : key.publicKey)
        return KeyFile(
            ageIdentity: identity, recipient: recipient, postQuantum: postQuantum, name: key.recipe.name, created: .now)
    }

    @Test(
        "a file is named for its tool and the key's letters and digits",
        arguments: [
            (KeyKind.ssh, "github", false, "id_ed25519_github"),
            (.ssh, "homelab host", false, "id_ed25519_homelab-host"),
            (.ssh, "👩‍💻 laptop", false, "id_ed25519_laptop"),
            (.ssh, "café / nas", false, "id_ed25519_café-nas"),
            (.ssh, "🧨", false, "id_ed25519"),
            (.age, "backups 2026", false, "age-backups-2026.txt"),
            (.age, "🇺🇸", false, "age.txt"),
            (.age, "backups 2026", true, "age-pq-backups-2026.txt"),
            (.age, "🇺🇸", true, "age-pq.txt")
        ])
    func names(kind: KeyKind, name: String, postQuantum: Bool, expected: String) throws {
        #expect(try file(kind, name, postQuantum: postQuantum).filename == expected)
    }

    @Test("an SSH file is the OpenSSH private key")
    func sshContents() throws {
        let key = DerivedKey.derive(seed: DiceKey.example.seed, recipe: try KeyRecipe(kind: .ssh, name: "github"))
        #expect(KeyFile(ssh: key).contents == key.secret)
    }

    @Test("an age file is written as age-keygen writes it", arguments: [false, true])
    func ageContents(postQuantum: Bool) throws {
        let key = DerivedKey.derive(seed: DiceKey.example.seed, recipe: try KeyRecipe(kind: .age, name: "backups"))
        let identity = try #require(postQuantum ? key.postQuantum?.identity : key.secret)
        let recipient = try #require(postQuantum ? key.postQuantum?.recipient : key.publicKey)
        let created = Date(timeIntervalSince1970: 1_763_378_117)
        let file = KeyFile(
            ageIdentity: identity, recipient: recipient, postQuantum: postQuantum, name: "backups", created: created)
        let lines = file.contents.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        #expect(lines.count == 4 && lines[3].isEmpty)
        let rfc3339 = /# created: (\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d(?:Z|[+-]\d\d:\d\d))/
        let stamp = try #require(lines[0].wholeMatch(of: rfc3339))
        #expect(try Date(String(stamp.1), strategy: .iso8601) == created)
        #expect(lines[1] == "# public key: \(recipient)")
        #expect(lines[2] == identity)
    }
}
