//
//  SequenceNumberField.swift
//  DiceKeys
//
//  Created by Stuart Schechter on 2020/12/18.
//

import SwiftUI

struct SequenceNumberView: View {
    @Binding var sequenceNumber: Int

    var body: some View {
        HStack {
            VStack(alignment: .center, spacing: 0) {
                TextField("1", value: $sequenceNumber, format: .number)
                    .font(.title)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 48)
                    .padding(.top, 2)
                    .keyboardType(.numberPad)
                Text("Sequence").font(.footnote).foregroundStyle(.secondary)
                Text("Number").font(.footnote).foregroundStyle(.secondary)
            }
            VStack {
                Button {
                    sequenceNumber += 1
                } label: {
                    Image(systemName: "arrow.up.square")
                        .resizable().aspectRatio(contentMode: .fit).frame(height: 28)
                }
                .buttonStyle(.plain)
                Button {
                    sequenceNumber = max(1, sequenceNumber - 1)
                } label: {
                    Image(systemName: "arrow.down.square")
                        .resizable().aspectRatio(contentMode: .fit).frame(height: 28)
                }
                .buttonStyle(.plain)
            }
        }
        .onChange(of: sequenceNumber) { _, newValue in
            if newValue < 1 { sequenceNumber = 1 }
        }
    }
}

struct SequenceNumberField: View {
    @Binding var sequenceNumber: Int

    var body: some View {
        HStack {
            Spacer()
            SequenceNumberView(sequenceNumber: $sequenceNumber)
            Spacer(minLength: 30)
            Text("If you need multiple passwords for a single website or service, change the sequence number to create additional passwords.")
                .foregroundStyle(Color.formInstructions)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                .minimumScaleFactor(0.01)
                .scaledToFit()
                .lineLimit(4)
            Spacer()
        }
    }
}

#Preview {
    @Previewable @State var number: Int = 1
    SequenceNumberField(sequenceNumber: $number)
}
