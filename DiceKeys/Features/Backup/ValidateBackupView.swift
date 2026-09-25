//
//  ValidateBackupView.swift
//  DiceKeys
//
//  Created by Stuart Schechter on 2020/12/07.
//

import SwiftUI

/// The last backup step: scan the copy and compare it with the original.
struct ValidateBackupView: View {
    let target: BackupTarget
    let originalDiceKey: DiceKey
    let onOriginalRescanned: (DiceKey) -> Void
    @Binding var backupScanned: DiceKey?

    @State private var scanningOriginal: Bool = false
    @State private var scanningCopy: Bool = false

    private var backupDiceKeyRotatedToMatchOriginal: DiceKey? {
        guard let backup = backupScanned else { return nil }
        return originalDiceKey.mostSimilarRotationOf(backup)
    }

    private var invalidIndexes: Set<Int> {
        guard let backup = backupDiceKeyRotatedToMatchOriginal else { return Set<Int>() }
        return Set<Int>(
            (0..<25).filter { originalDiceKey.faces[$0].numberOfFieldsDifferent(fromOtherFace: backup.faces[$0]) > 0 }
        )
    }

    private var perfectMatch: Bool {
        invalidIndexes.isEmpty && backupScanned != nil
    }

    private var totalMismatch: Bool {
        invalidIndexes.count > 5
    }

    private var scanningBackupImageName: String {
        return target == .Stickeys ? "Scanning a Stickey" : "Scanning a DiceKey PNG"
    }

    var body: some View {
        Instruction("Scan your backup to validate it.", lineLimit: 1)
        Spacer()
        if scanningCopy || scanningOriginal {
            ScanDiceKeyView(
                stickers: target == .Stickeys,
                onDiceKeyRead: { diceKeyScanned in
                    if scanningOriginal {
                        onOriginalRescanned(diceKeyScanned)
                        scanningOriginal = false
                    } else if scanningCopy {
                        backupScanned = diceKeyScanned
                        scanningCopy = false
                    }
                },
                onCancel: {
                    scanningCopy = false
                    scanningOriginal = false
                }
            )
            Spacer()
        } else if let backup = backupDiceKeyRotatedToMatchOriginal, let backupScanned {
            HStack(alignment: .top) {
                VStack {
                    DiceKeyView(diceKey: originalDiceKey)
                    PrimaryButton("Re-scan") { scanningOriginal = true }.hideIf(perfectMatch)
                }
                Spacer()
                VStack {
                    if totalMismatch {
                        DiceKeyView(diceKey: backupScanned)
                    } else {
                        DiceKeyView(diceKey: backup, highlightIndexes: invalidIndexes)
                    }
                    PrimaryButton("Re-scan copy") { scanningCopy = true }.hideIf(perfectMatch)
                }
            }
            Spacer()
            if perfectMatch {
                Text("You made a perfect copy!")
                    .font(Font.system(size: 500))
                    .minimumScaleFactor(0.01)
                    .scaledToFit()
                    .lineLimit(1)
                    .foregroundStyle(.green)
            } else if totalMismatch {
                Text("That key doesn't look at all like the key you scanned before.").font(.title).foregroundStyle(.red)
            } else {
                Text("You incorrectly copied the highlighted \(invalidIndexes.count == 1 ? "die" : "dice"). You can fix the copy to match the original, or change the original to match the copy.").font(.title).foregroundStyle(.red)
            }
            Spacer()
        } else {
            HStack(alignment: .center) {
                VStack {
                    DiceKeyView(diceKey: originalDiceKey)
                    PrimaryButton("Scan DiceKey") { scanningOriginal = true }.hidden()
                }
                VStack {
                    Image(scanningBackupImageName)
                        .resizable().scaledToFit()
                        .offset(x: 0, y: -50)
                    PrimaryButton("Scan copy to validate") { scanningCopy = true }
                }
            }
        }
        Spacer()
    }
}

#Preview {
    @Previewable @State var backupScanned: DiceKey?
    VStack {
        ValidateBackupView(target: .Stickeys, originalDiceKey: DiceKey.createFromRandom(), onOriginalRescanned: { _ in }, backupScanned: $backupScanned)
    }
}
