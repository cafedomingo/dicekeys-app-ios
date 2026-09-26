//
//  StepFooter.swift
//  DiceKeys
//
//  Created by Stuart Schechter on 2020/12/16.
//

import SwiftUI

/// Previous / Next navigation for multi-step instructions (assembly, backup).
struct StepFooterView: View {
    let goTo: (Int) -> Void
    let prevPrev: (() -> Void)?
    let prev: (() -> Void)?
    let next: (() -> Void)?
    let nextNext: (() -> Void)?
    let setMaySkip: (() -> Void)?
    let isLastStep: Bool

    init(goTo: @escaping (Int) -> Void,
         prevPrev: (() -> Void)? = nil,
         prev: (() -> Void)? = nil,
         next: (() -> Void)? = nil,
         nextNext: (() -> Void)? = nil,
         setMaySkip: (() -> Void)? = nil,
         isLastStep: Bool
    ) {
        self.goTo = goTo
        self.prevPrev = prevPrev
        self.prev = prev
        self.next = next
        self.nextNext = nextNext
        self.setMaySkip = setMaySkip
        self.isLastStep = isLastStep
    }

    init(goTo: @escaping (Int) -> Void,
         step: Int,
         prevPrev: Int? = nil,
         prev: Int? = nil,
         next: Int? = nil,
         nextNext: Int? = nil,
         setMaySkip: (() -> Void)? = nil,
         isLastStep: Bool
    ) {
        self.goTo = goTo
        func goToIfDefined(_ condition: Bool, _ dest: Int?) -> (() -> Void)? {
            guard let dest, condition else { return nil }
            return { goTo(dest) }
        }
        let prevIsBefore = prev.map { $0 < step } ?? false
        let nextIsAfter = next.map { $0 > step } ?? false
        self.prevPrev = goToIfDefined(prevIsBefore && (prevPrev.map { pp in prev.map { pp < $0 } ?? false } ?? false), prevPrev)
        self.prev = goToIfDefined(prevIsBefore, prev)
        self.next = goToIfDefined(nextIsAfter, next)
        self.nextNext = goToIfDefined(nextIsAfter && (nextNext.map { nn in next.map { nn > $0 } ?? false } ?? false), nextNext)
        self.setMaySkip = setMaySkip
        self.isLastStep = isLastStep
    }

    var body: some View {
        VStack(spacing: 8) {
            Button("Let me skip this step") { setMaySkip?() }
                .font(.body)
                .showIf(setMaySkip != nil)
            // Hidden buttons keep their space (`showIf` uses `.hidden()`), so the row
            // is laid out for all four; fixedSize stops the titles wrapping when the
            // stack proposes each button a fraction of the width.
            HStack(spacing: 12) {
                Button { prevPrev?() } label: {
                    Image(systemName: "chevron.backward.2")
                }
                .buttonStyle(.glass)
                .accessibilityLabel("Back to the start")
                .showIf(prevPrev != nil)
                Button { prev?() } label: {
                    Label("Previous", systemImage: "chevron.backward")
                        .font(.title3)
                }
                .buttonStyle(.glass)
                .controlSize(.large)
                .fixedSize()
                .showIf(prev != nil)
                Spacer(minLength: 0)
                Button { next?() } label: {
                    HStack {
                        Text(isLastStep ? "Done" : "Next").font(.title3)
                        Image(systemName: "chevron.forward")
                    }
                }
                .buttonStyle(.glassProminent)
                .controlSize(.large)
                .fixedSize()
                .disabled(setMaySkip != nil)
                .showIf(next != nil)
                Button { nextNext?() } label: {
                    Image(systemName: "chevron.forward.2")
                }
                .buttonStyle(.glass)
                .accessibilityLabel("Skip to the end")
                .showIf(nextNext != nil)
            }
        }
    }
}

#Preview {
    StepFooterView(goTo: { _ in }, step: 2, prevPrev: 0, prev: 1, next: 3, nextNext: 4, isLastStep: false)
}
