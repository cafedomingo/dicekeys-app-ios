//
//  ChooseBackupTargetView.swift
//  DiceKeys
//
//  Created by Stuart Schechter on 2020/11/28.
//

import SwiftUI

/// Step 0 of the backup: copy to a Stickeys kit or to another DiceKey kit?
struct ChooseBackupTargetView: View {
    let diceKey: DiceKey
    let choice: (BackupTarget) -> Void

    var body: some View {
        VStack(alignment: .center) {
            Instruction("Make a backup of your DiceKey by copying it.", lineLimit: 2)
            Spacer()
            Button {
                choice(.Stickeys)
            } label: {
                VStack {
                    HStack(alignment: .center, spacing: 0) {
                        Spacer()
                        DiceKeyView(diceKey: diceKey, hideFaces: true, diceBoxColor: .alexandrasBlue, diePenColor: .alexandrasBlue,
                                    aspectRatioMatchStickeys: true)
                            .frame(minWidth: 0, maxWidth: .infinity)
                        Image(systemName: "arrow.right.circle.fill")
                            .foregroundStyle(Color.alexandrasBlue)
                            .scaleEffect(2.0)
                            .padding(.horizontal, 20)
                        StickerTargetSheet(diceKey: diceKey, showLettersBeforeIndex: 12, atDieIndex: 12, foregroundColor: Color.alexandrasBlue, orientation: .portrait)
                            .frame(minWidth: 0, maxWidth: .infinity)
                        Spacer()
                    }
                    Text("Use a Stickeys Kit").font(.title).foregroundStyle(Color.alexandrasBlue)
                }
                .contentShape(Rectangle())
            }
            .frame(minHeight: 0, maxHeight: .infinity)
            .buttonStyle(.plain)
            Spacer(minLength: 20)
            Button {
                choice(.DiceKey)
            } label: {
                VStack {
                    HStack(alignment: .center, spacing: 0) {
                        Spacer()
                        DiceKeyView(diceKey: diceKey, hideFaces: true, diceBoxColor: .alexandrasBlue, diePenColor: .alexandrasBlue,
                                    aspectRatioMatchStickeys: true)
                            .frame(minWidth: 0, maxWidth: .infinity)
                        Image(systemName: "arrow.right.circle.fill")
                            .foregroundStyle(Color.alexandrasBlue)
                            .scaleEffect(2.0)
                            .padding(.horizontal, 20)
                        DiceKeyCopyInProgress(diceKey: diceKey, atDieIndex: 12, diceBoxColor: .alexandrasBlue, diePenColor: .alexandrasBlue)
                            .frame(minWidth: 0, maxWidth: .infinity)
                        Spacer()
                    }
                    Text("Use a DiceKey Kit").font(.title).foregroundStyle(Color.alexandrasBlue)
                }
                .contentShape(Rectangle())
            }
            .frame(minHeight: 0, maxHeight: .infinity)
            .buttonStyle(.plain)
            Spacer()
        }
    }
}

#Preview {
    ChooseBackupTargetView(diceKey: DiceKey.createFromRandom(), choice: { _ in })
}
