//
//  AlgorithmDisplay.swift
//  DiceKeyVault
//

import Derivation

/// How one algorithm of a kind shows on a key and while it is made.
struct AlgorithmDisplay: Equatable {
    /// Heads its public key's section, and labels its secret when a kind has several.
    let title: String
    /// When to use its public key, under it in place of a fingerprint.
    var note: String?
    /// For a public key too long to read whole: it opens folded to this many lines.
    var foldedLines: Int?
    /// The file its tool reads, which its secret is shared as.
    var file: KeyFile.Name?
}

extension KeyKind {
    private static let x25519Note =
        "For any version of age. A file can be encrypted to it alongside SSH and other X25519 recipients."
    private static let postQuantumNote =
        "Safe from future quantum computers. Needs age 1.3 or later, and a file encrypted to it can't also be encrypted to X25519 or SSH recipients."
    /// The recipient is about 1,950 characters, so it opens folded to this many lines.
    private static let postQuantumFoldedLines = 4

    /// What shows for one of this kind's algorithms. Add a row here with each algorithm.
    func display(of type: DerivableType) -> AlgorithmDisplay {
        switch (self, type) {
        case (.ssh, .ed25519):
            AlgorithmDisplay(title: "Public key", file: .init(base: "id_ed25519", separator: "_", suffix: ""))
        case (.wireguard, .x25519):
            AlgorithmDisplay(title: "Public key")
        case (.age, .x25519):
            AlgorithmDisplay(
                title: "X25519", note: Self.x25519Note, file: .init(base: "age", separator: "-", suffix: ".txt"))
        case (.age, .mlkem768x25519):
            AlgorithmDisplay(
                title: "ML-KEM-768 + X25519 (post-quantum)", note: Self.postQuantumNote,
                foldedLines: Self.postQuantumFoldedLines,
                file: .init(base: "age-pq", separator: "-", suffix: ".txt"))
        case (.passphrase, .passphrase):
            AlgorithmDisplay(title: "Passphrase")
        case (.wallet, .bip39):
            AlgorithmDisplay(title: "Recovery phrase")
        default:
            AlgorithmDisplay(title: type.rawValue)
        }
    }
}
