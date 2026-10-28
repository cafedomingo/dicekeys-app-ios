//
//  AlgorithmDisplayTests.swift
//  DiceKeyVaultTests
//

import Derivation
import Testing

@testable import DiceKeyVault

struct AlgorithmDisplayTests {
    private static let x25519Note =
        "For any version of age. A file can be encrypted to it alongside SSH and other X25519 recipients."
    private static let postQuantumNote =
        "Safe from future quantum computers. Needs age 1.3 or later, and a file encrypted to it can't also be encrypted to X25519 or SSH recipients."

    /// Each kind's displays, in the order of its algorithms.
    private static let table: [KeyKind: [AlgorithmDisplay]] = [
        .ssh: [
            AlgorithmDisplay(
                title: "Public key", file: KeyFile.Name(base: "id_ed25519", separator: "_", suffix: ""))
        ],
        .wireguard: [AlgorithmDisplay(title: "Public key")],
        .age: [
            AlgorithmDisplay(
                title: "X25519", note: x25519Note, file: KeyFile.Name(base: "age", separator: "-", suffix: ".txt")),
            AlgorithmDisplay(
                title: "ML-KEM-768 + X25519 (post-quantum)", note: postQuantumNote, foldedLines: 4,
                file: KeyFile.Name(base: "age-pq", separator: "-", suffix: ".txt"))
        ],
        .passphrase: [AlgorithmDisplay(title: "Passphrase")],
        .wallet: [AlgorithmDisplay(title: "Recovery phrase")]
    ]

    @Test("every algorithm of every kind shows as the table says", arguments: KeyKind.allCases)
    func table(kind: KeyKind) {
        #expect(kind.algorithms.map { kind.display(of: $0) } == Self.table[kind])
    }

    @Test("a pair the table doesn't know is titled by its type")
    func unknownPair() {
        #expect(KeyKind.ssh.display(of: .x25519) == AlgorithmDisplay(title: "x25519"))
    }
}
