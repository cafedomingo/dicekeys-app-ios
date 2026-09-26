//
//  DerivedValueQrCodeSheet.swift
//  DiceKeys
//

import SwiftUI

/// The QR code for a derived value, shown as a sheet. The user first says what
/// will read the code, because iPhone cameras can leak the value to a web search.
struct DerivedValueQrCodeSheet: View {
    @Environment(\.dismiss) private var dismiss
    let title: String
    let content: String

    @State private var askForUsage = true
    @State private var warnAboutiOS = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    if !askForUsage {
                        qrCode
                    } else if !warnAboutiOS {
                        usageQuestion
                    } else {
                        iOSWarning
                    }
                }
                .padding(20)
            }
            .scrollEdgeEffectStyle(.soft, for: .top)
            .navigationTitle(title)
            .toolbarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("OK") { dismiss() }
                }
            }
        }
    }

    @ViewBuilder
    private var qrCode: some View {
        if let qrImage = content.toQRCode() {
            Image(decorative: qrImage, scale: 1)
                .resizable()
                .interpolation(.none)
                .scaledToFit()
                .padding(8)
                .background(Color.white)
                .clipShape(RoundedRectangle(cornerRadius: 12))
        } else {
            Text("This value cannot be encoded as a QR code.")
        }
        Text(content)
            .font(.caption)
            .lineLimit(1)
    }

    @ViewBuilder
    private var usageQuestion: some View {
        Text("I will be reading this QR code with:")
            .font(.subheadline)
        Button {
            warnAboutiOS = true
        } label: {
            Text("The camera app on an iPhone or iPad")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.glass)
        Button {
            askForUsage = false
        } label: {
            Text("The camera app on an Android phone or tablet")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.glass)
        Button {
            askForUsage = false
        } label: {
            Text("A different app or device")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.glass)
    }

    @ViewBuilder
    private var iOSWarning: some View {
        Text("Caution: iPhone and iPads can leak secrets from QR codes")
            .bold()
            .frame(maxWidth: .infinity, alignment: .leading)
        Text("Clicking on the notification that appears when the camera has scanned your QR code will start a web search. The web search sends your secrets to your search engine over the Internet. Your search engine will likely store them.\n\nTo prevent your secrets from being exposed, swipe the notification downward to the bottom of the screen to expose the copy option. This option copies the secret to the clipboard on your device.")
            .font(.caption)
            .frame(maxWidth: .infinity)
        Button("Got it. I'll be careful") {
            askForUsage = false
        }
        .buttonStyle(.glassProminent)
    }
}

#Preview {
    DerivedValueQrCodeSheet(title: "Password", content: "15-Rerun-pound-grout-limit")
}
