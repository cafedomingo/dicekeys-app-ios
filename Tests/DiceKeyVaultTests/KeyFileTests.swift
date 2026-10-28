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
    private func algorithm(_ kind: KeyKind, _ name: String, _ index: Int = 0) throws -> AlgorithmKey {
        DerivedKey.derive(seed: DiceKey.example.seed, recipe: try KeyRecipe(kind: kind, name: name)).algorithms[index]
    }

    @Test(
        "a file is named for its tool and the key's letters and digits",
        arguments: [
            (KeyKind.ssh, "github", 0, "id_ed25519_github"),
            (.ssh, "homelab host", 0, "id_ed25519_homelab-host"),
            (.ssh, "👩‍💻 laptop", 0, "id_ed25519_laptop"),
            (.ssh, "café / nas", 0, "id_ed25519_café-nas"),
            (.ssh, "🧨", 0, "id_ed25519"),
            (.age, "backups 2026", 0, "age-backups-2026.txt"),
            (.age, "🇺🇸", 0, "age.txt"),
            (.age, "backups 2026", 1, "age-pq-backups-2026.txt"),
            (.age, "🇺🇸", 1, "age-pq.txt")
        ])
    func names(kind: KeyKind, name: String, index: Int, expected: String) throws {
        let key = try algorithm(kind, name, index)
        let file = try #require(KeyFile(kind: kind, algorithm: key, name: name, created: .now))
        #expect(file.filename == expected)
    }

    @Test("a key no tool reads from a file is not a file", arguments: [KeyKind.wireguard, .passphrase])
    func noFile(kind: KeyKind) throws {
        let key = try algorithm(kind, "home")
        #expect(KeyFile(kind: kind, algorithm: key, name: "home", created: .now) == nil)
    }

    @Test("an SSH file is the OpenSSH private key")
    func sshContents() throws {
        let key = try algorithm(.ssh, "github")
        #expect(KeyFile(kind: .ssh, algorithm: key, name: "github", created: .now)?.contents == key.secret)
    }

    @Test("an age file is written as age-keygen writes it", arguments: [0, 1])
    func ageContents(index: Int) throws {
        let key = try algorithm(.age, "backups", index)
        let recipient = try #require(key.publicKey)
        let created = Date(timeIntervalSince1970: 1_763_378_117)
        let file = try #require(KeyFile(kind: .age, algorithm: key, name: "backups", created: created))
        let lines = file.contents.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        #expect(lines.count == 4 && lines[3].isEmpty)
        let rfc3339 = /# created: (\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d(?:Z|[+-]\d\d:\d\d))/
        let stamp = try #require(lines[0].wholeMatch(of: rfc3339))
        #expect(try Date(String(stamp.1), strategy: .iso8601) == created)
        #expect(lines[1] == "# public key: \(recipient)")
        #expect(lines[2] == key.secret)
    }

    @Test("an age file without its recipient is not a file")
    func ageNeedsRecipient() throws {
        let key = try algorithm(.age, "backups")
        let bare = AlgorithmKey(type: key.type, publicKey: nil, fingerprint: nil, secret: key.secret)
        #expect(KeyFile(kind: .age, algorithm: bare, name: "backups", created: .now) == nil)
    }
}
