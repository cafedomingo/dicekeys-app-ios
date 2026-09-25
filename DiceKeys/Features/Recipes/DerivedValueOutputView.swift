//
//  DerivedValueOutputView.swift
//  DiceKeys
//

import SwiftUI

/// The output section of `DerivedValueScreen`: format picker, QR button, the
/// DiceKey-to-value funnel, and a copy button.
struct DerivedValueOutputView: View {
    let diceKey: DiceKey
    let derivedValue: any DerivedValue
    @Binding var format: DerivedValueView
    let onShowQrCode: () -> Void

    private var valueText: String {
        derivedValue.valueForView(view: format)
    }

    var body: some View {
        VStack(alignment: .center, spacing: 0) {
            HStack {
                Text("Output Format:")
                Picker("Output Format", selection: $format) {
                    ForEach(derivedValue.views.reversed()) { view in
                        Text(view.description).tag(view)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                Spacer()
                Button(action: onShowQrCode) {
                    Image("QR Code")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 30, height: 30)
                }
                .accessibilityLabel("Show QR code")
                .padding(.trailing, 10)
            }
            .padding(.horizontal, 10)

            DerivedFromDiceKey(diceKey: diceKey) {
                Text(valueText)
                    .padding(3)
                    .foregroundStyle(.white)
                    .font(.body)
                    .multilineTextAlignment(.center)
                    .lineLimit(8)
                    .minimumScaleFactor(0.4)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 5)
            .layoutPriority(-1)

            if !valueText.isEmpty {
                Button("Copy \(format.description)") {
                    valueText.copyToPasteboard()
                }
                .buttonStyle(.glass)
                .padding(.bottom, 4)
            }
        }
    }
}

#Preview {
    @Previewable @State var format: DerivedValueView = .Password
    let diceKey = DiceKey.createFromRandom()
    DerivedValueOutputView(
        diceKey: diceKey,
        derivedValue: try! derivationRecipeTemplates[0].derivedValue(diceKey: diceKey),
        format: $format,
        onShowQrCode: {}
    )
}
