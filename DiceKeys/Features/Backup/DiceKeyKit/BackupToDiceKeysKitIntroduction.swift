//
//  BackupToDiceKeysKitIntroduction.swift
//  DiceKeys
//
//  Created by Stuart Schechter on 2020/12/07.
//

import SwiftUI

struct BackupToDiceKeysKitIntroduction: View {
    let diceKey: DiceKey

    var body: some View {
        VStack {
            Spacer()
            Instruction("Open your DiceKey kit and take out the box bottom and the 25 dice.", lineLimit: 3)
            Spacer()
            DiceKeyView(diceKey: diceKey, showDiceAtIndexes: Set())
                .containerRelativeFrame(.horizontal) { length, _ in length / 6 }
            Spacer()
            Instruction("Next, you will replicate the first DiceKey by copying the arrangement of dice.", lineLimit: 3)
            HStack(alignment: .center, spacing: 0) {
                Spacer()
                Text("Need another DiceKey? You can ")
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                if let store = URL(string: "https://dicekeys.com/store") {
                    Link("order more", destination: store)
                }
                Text(".")
            }.padding(.top, 30)
            Spacer()
        }
    }
}

#Preview {
    BackupToDiceKeysKitIntroduction(diceKey: DiceKey.createFromRandom())
}
