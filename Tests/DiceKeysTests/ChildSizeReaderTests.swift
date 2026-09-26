//
//  ChildSizeReaderTests.swift
//  DiceKeysTests
//
//  A size reader must report its own content's size even when views inside it measure
//  themselves too. TransferSticker nests the two sticker sheets (each a CalculateBounds)
//  in a ChildSizeReader; when their sizes leaked into its reading, the backup screen drew
//  the transfer line across one sheet instead of from sheet to sheet.
//

import SwiftUI
import Testing
import UIKit
@testable import DiceKeys

@MainActor
private final class Reported {
    var size: CGSize = .zero
}

private struct SelfMeasuring: View {
    @State private var bounds: CGSize = .zero
    var body: some View {
        CalculateBounds(bounds: $bounds) { Color.red }
    }
}

private struct NestedReaders: View {
    let reported: Reported
    @State private var outer: CGSize = .zero

    var body: some View {
        ChildSizeReader(size: $outer) {
            HStack(spacing: 0) {
                SelfMeasuring().frame(width: 100, height: 50)
                SelfMeasuring().frame(width: 60, height: 50)
            }
        }
        .onChange(of: outer) { _, size in reported.size = size }
    }
}

@MainActor
struct ChildSizeReaderTests {
    @Test("an outer reader reports its content's size, not a nested reader's")
    func nestedReadersDoNotLeak() async throws {
        let scene = try #require(UIApplication.shared.connectedScenes.first as? UIWindowScene)
        let window = UIWindow(windowScene: scene)
        let reported = Reported()
        window.rootViewController = UIHostingController(rootView: NestedReaders(reported: reported))
        window.makeKeyAndVisible()
        defer { window.isHidden = true }
        for _ in 0..<20 where reported.size == .zero {
            window.layoutIfNeeded()
            try await Task.sleep(for: .milliseconds(50))
        }
        #expect(reported.size == CGSize(width: 160, height: 50))
    }
}
