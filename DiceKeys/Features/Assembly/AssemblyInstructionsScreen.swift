//
//  AssemblyInstructionsScreen.swift
//  DiceKeys
//

import SwiftUI

struct SingleLineScaledText: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text).font(Font.system(size: 500, weight: .bold))
            .minimumScaleFactor(0.01)
            .scaledToFit()
            .lineLimit(1)
    }
}

private struct Warning: View {
    let message: String

    var body: some View {
        HStack {
            Spacer()
            Text(message.uppercased()).bold()
                .minimumScaleFactor(0.01)
                .scaledToFit()
                .lineLimit(1)
            Spacer()
        }
    }
}

private struct Randomize: View {
    var body: some View {
        Instruction("Shake the dice in the felt bag or in your hands.")
        Spacer()
        Image("Illustration of shaking bag").resizable().scaledToFit()
        Spacer()
    }
}

private struct DropDice: View {
    var body: some View {
        Instruction("Let the dice fall randomly.")
        Spacer()
        Image("Box Bottom After Roll").resizable().scaledToFit()
        Spacer()
        Instruction("Most should land squarely into the 25 slots in the box base.")
        Spacer()
    }
}

private struct FillEmptySlots: View {
    var body: some View {
        Instruction("Put the remaining dice squarely into the empty slots.")
        Spacer()
        Image("Box Bottom All Dice In Place").resizable().scaledToFit()
        Spacer()
        Instruction("Leave the rest in their original random order and orientations.")
        Spacer()
    }
}

private struct ScanFirstTime: View {
    @State private var scanning: Bool = false
    @Binding var diceKey: DiceKey?

    var body: some View {
        Instruction("Scan the dice in the bottom of the box (without the top.)")
        Spacer()
        if let diceKey {
            DiceKeyView(diceKey: diceKey)
            PrimaryButton("Scan again") {
                self.diceKey = nil
                scanning = true
            }
        } else if scanning {
            ScanDiceKeyView(
                onDiceKeyRead: {
                    diceKey = $0
                    scanning = false
                },
                onCancel: { scanning = false })
        } else {
            Image(.scanningADiceKey).resizable().scaledToFit().offset(x: 0, y: -50)
            PrimaryButton("Scan") { scanning = true }
        }
        Spacer()
    }
}

private struct SealBox: View {
    var body: some View {
        Instruction("Place the box top above the base so that the hinges line up.")
        Spacer()
        Image("Seal Box").resizable().scaledToFit()
        Spacer()
        Instruction(
            "Press firmly down along the edges. The box will snap together, helping to prevent accidental re-opening.")
        Spacer()
    }
}

private struct InstructionsDone: View {
    let createdDiceKey: Bool
    let backedUpSuccessfully: Bool

    var body: some View {
        SingleLineScaledText(createdDiceKey ? "You did it!" : "That's it!")
        Spacer()
        if !createdDiceKey {
            Instruction("There's nothing more to it.")
            Spacer()
            Instruction("Go back to assemble and scan in a real DiceKey.").padding(.top, 5)
            Spacer()
        } else if !backedUpSuccessfully {
            Instruction("Be sure to make a backup soon!")
            Spacer()
        }
        if createdDiceKey {
            Instruction(
                "When you press the \"Done\" button, we'll take you to the same screen you'll see after scanning your DiceKey from the home screen."
            )
            Spacer()
        }
    }
}

struct AssemblyInstructionsScreen: View {
    @Environment(\.dismiss) private var dismiss

    var onSuccess: ((DiceKey) -> Void)?

    enum Step: Int {
        case randomize = 1
        case dropDice
        case fillEmptySlots
        case scanFirstTime
        case createBackup
        case sealBox
        case done
    }

    @State private var diceKeyScanned: DiceKey?
    @State private var backupScanned: DiceKey?
    @State private var step: Step = .randomize
    @State private var backupProgress = BackupProgress(target: .stickeys)
    @State private var userChoseToAllowSkipScanningStep: Bool = false

    private let last = Step.done.rawValue

    private var backupSuccessful: Bool {
        DiceKey.rotationIndependentEquals(diceKeyScanned, backupScanned)
    }

    private var showWarning: Bool {
        step.rawValue > Step.randomize.rawValue && step.rawValue < Step.sealBox.rawValue
    }

    var body: some View {
        VStack {
            Spacer()
            VStack(alignment: .center) {
                switch step {
                case .randomize: Randomize()
                case .dropDice: DropDice()
                case .fillEmptySlots: FillEmptySlots()
                case .scanFirstTime: ScanFirstTime(diceKey: $diceKeyScanned)
                case .createBackup:
                    BackupDiceKeyView(
                        diceKey: diceKeyScanned ?? DiceKey.example,
                        onDiceKeyReplaced: { diceKeyScanned = $0 },
                        onComplete: { step = Step(rawValue: step.rawValue + 1) ?? .done },
                        onBackedOut: { step = Step(rawValue: step.rawValue - 1) ?? .randomize },
                        thereAreMoreStepsAfterBackup: true,
                        progress: backupProgress
                    )
                case .sealBox: SealBox()
                case .done:
                    InstructionsDone(createdDiceKey: diceKeyScanned != nil, backedUpSuccessfully: backupSuccessful)
                }
            }
            .padding(.horizontal, 15)
            Spacer()
            // Forward / Back nav
            if step != .createBackup {
                StepFooterView(
                    goTo: { destination in
                        if let newStep = Step(rawValue: destination) {
                            step = newStep
                        } else {
                            if let diceKey = diceKeyScanned, destination > last {
                                onSuccess?(diceKey)
                            } else {
                                dismiss()
                            }
                        }
                    },
                    step: step.rawValue,
                    prev: step.rawValue > 0 ? step.rawValue - 1 : nil,
                    next: step.rawValue + 1,
                    setMaySkip: step == .scanFirstTime && diceKeyScanned == nil && !userChoseToAllowSkipScanningStep
                        ? { userChoseToAllowSkipScanningStep = true }
                        : nil,
                    isLastStep: step == .done
                )
                .padding(.bottom)
            }
        }
        .safeAreaInset(edge: .bottom) {
            if showWarning {
                Warning(message: "Do not close the box before the final Step.")
                    .padding(.vertical, 5)
                    .frame(maxWidth: .infinity)
                    .foregroundStyle(Color.Interface.onWarning)
                    .background(Color.Interface.warningBackground)
            }
        }
        .navigationTitle("Assemble a DiceKey")
        .toolbarTitleDisplayMode(.inline)
    }
}

#Preview {
    NavigationStack {
        AssemblyInstructionsScreen()
    }
    .appEnvironment(AppModel.preview())
}
