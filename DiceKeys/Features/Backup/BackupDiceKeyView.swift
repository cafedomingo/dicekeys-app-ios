//
//  BackupDiceKeyView.swift
//  DiceKeys
//
//  Created by Stuart Schechter on 2020/11/28.
//

import SwiftUI

/// The multi-step backup flow: choose a target, copy each die, validate.
struct BackupDiceKeyView: View {
    let diceKey: DiceKey
    /// Called when re-scanning during validation replaces the original DiceKey.
    let onDiceKeyReplaced: (DiceKey) -> Void
    let onComplete: () -> Void
    var onBackedOut: (() -> Void)?
    var thereAreMoreStepsAfterBackup: Bool = false
    let progress: BackupProgress

    @State private var backupScanned: DiceKey?
    @State private var maySkipValidationStep = false

    private var step: Int { progress.step }
    private var target: BackupTarget? { progress.target }

    private var validationRequired: Bool {
        step == validationStep && !DiceKey.rotationIndependentEquals(diceKey, backupScanned) && !maySkipValidationStep
    }

    private let validationStep = 27
    private let lastStep = 27

    var body: some View {
        VStack {
            if let target, step > 0 {
                if step < validationStep {
                    BackupStepsView(diceKey: diceKey, target: target, step: step)
                } else {
                    ValidateBackupView(
                        target: target,
                        originalDiceKey: diceKey,
                        onOriginalRescanned: onDiceKeyReplaced,
                        backupScanned: $backupScanned
                    )
                }
            } else {
                ChooseBackupTargetView(diceKey: diceKey) { chosenTarget in
                    progress.target = chosenTarget
                    progress.step = 1
                }
            }
            StepFooterView(
                goTo: { destination in
                    if destination < 0 {
                        onBackedOut?()
                    } else if destination <= lastStep {
                        progress.step = destination
                    } else {
                        onComplete()
                    }
                },
                step: step,
                prevPrev: 1,
                prev: (step > 0 || onBackedOut != nil) ? step - 1 : nil,
                next: step == 0 ? nil : step + 1,
                nextNext: validationStep,
                setMaySkip: validationRequired ? { maySkipValidationStep = true } :
                    step == 0 && thereAreMoreStepsAfterBackup ? { onComplete() } :
                    nil,
                isLastStep: step == lastStep && !thereAreMoreStepsAfterBackup
            )
        }
        .padding(.horizontal, 10)
        .padding(.bottom, 10)
    }
}

/// Steps 1...26 of the backup: the kit introduction, then one die at a time.
private struct BackupStepsView: View {
    let diceKey: DiceKey
    let target: BackupTarget
    let step: Int

    private var faceIndex: Int { step - 2 }

    var body: some View {
        if step == 1 {
            switch target {
            case .Stickeys: BackupToStickeysIntroduction(diceKey: diceKey)
            case .DiceKey: BackupToDiceKeysKitIntroduction(diceKey: diceKey)
            }
        } else if step >= 2 && step <= 26 {
            Instruction("Construct your Backup", lineLimit: 1)
            Spacer()
            switch target {
            case .Stickeys: TransferSticker(diceKey: diceKey, faceIndex: faceIndex)
            case .DiceKey: TransferDie(diceKey: diceKey, faceIndex: faceIndex)
            }

            ZStack(alignment: Alignment(horizontal: .leading, vertical: .top)) {
                // To ensure consistent spacing as we walk through instructions
                // render instructions for all 25 dice and hide the 24 not being
                // shown right now
                ForEach(0..<25, id: \.self) { index in
                    switch target {
                    case .Stickeys: TransferStickerInstructions(diceKey: diceKey, faceIndex: index).hideIf(index != faceIndex)
                    case .DiceKey: TransferDieInstructions(diceKey: diceKey, faceIndex: index).hideIf(index != faceIndex)
                    }
                }
            }
            .padding(.top, 20)
            Spacer()
        } else {
            EmptyView()
        }
    }
}

#Preview {
    BackupDiceKeyView(
        diceKey: DiceKey.createFromRandom(),
        onDiceKeyReplaced: { _ in },
        onComplete: {},
        progress: BackupProgress()
    )
}
