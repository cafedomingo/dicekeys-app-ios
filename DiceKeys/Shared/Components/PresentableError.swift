//
//  PresentableError.swift
//  DiceKeys
//
//  The one pattern for surfacing async failures in the UI: a store or view
//  catches an error into a `PresentableError?` and a view shows it with
//  `.errorAlert(_:)`.
//

import SwiftUI

struct PresentableError: Identifiable, Equatable, Sendable {
    let id = UUID()
    let title: String
    let message: String

    init(title: String, error: any Error) {
        self.title = title
        self.message = error.localizedDescription
    }
}

extension View {
    /// Presents a `PresentableError` as a standard alert and clears it on dismissal.
    func errorAlert(_ error: Binding<PresentableError?>) -> some View {
        alert(
            error.wrappedValue?.title ?? "",
            isPresented: Binding(
                get: { error.wrappedValue != nil },
                set: { isPresented in if !isPresented { error.wrappedValue = nil } }
            ),
            presenting: error.wrappedValue
        ) { _ in
            Button("OK", role: .cancel) {}
        } message: { error in
            Text(error.message)
        }
    }
}
