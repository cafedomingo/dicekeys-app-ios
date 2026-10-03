//
//  CustomRecipeForm.swift
//  DiceKeys
//

import Derivation
import SwiftUI

/// The form for `CustomRecipeModel`: purpose, an optional length for secrets, and the
/// sequence number.
struct CustomRecipeForm: View {
    @Bindable var model: CustomRecipeModel

    var body: some View {
        Form {
            Section("What Is This Recipe For?") {
                TextField("purpose", text: $model.purposeString)
                    .plainTextEntry()
                Text("Enter a purpose for the " + model.type.descriptionForRecipeBuilder)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            if model.type == .secret {
                Section(
                    "Length, in Bytes (\(CustomRecipeModel.lengthInBytesEntryRange.lowerBound) - \(CustomRecipeModel.lengthInBytesEntryRange.upperBound))"
                ) {
                    TextField(String(Recipe.defaultLengthInBytes), value: $model.lengthInBytesEntry, format: .number)
                        .keyboardType(.numberPad)
                }
            }
            Section("Sequence Number") {
                SequenceNumberField(sequenceNumber: $model.sequenceNumber)
            }
        }
        .formStyle(.grouped)
    }
}

#Preview {
    CustomRecipeForm(model: CustomRecipeModel(type: .secret))
}
