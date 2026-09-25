//
//  BackupProgress.swift
//  DiceKeys
//

import Observation

enum BackupTarget: String, Sendable {
    case DiceKey
    case Stickeys
}

/// Where the user is in the backup flow. Owned by the screen that hosts
/// `BackupDiceKeyView` so that progress survives switching tabs.
@MainActor @Observable
final class BackupProgress {
    // Step 0: choose backup target
    // Step 1: Introduction
    // Step 2-26, assign key
    // Step 27, validate
    var step: Int = 0
    var target: BackupTarget?

    init(target: BackupTarget? = nil) {
        self.target = target
    }
}
