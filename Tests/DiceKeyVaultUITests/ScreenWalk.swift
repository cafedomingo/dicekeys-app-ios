//
//  ScreenWalk.swift
//  DiceKeyVaultUITests
//
//  Walks every screen the Simulator can reach and saves a screenshot at each stop, so a
//  visual change can be judged screen by screen in both appearances. Run it with
//  scripts/screen-walk.sh, which sets the appearance before each run: the Simulator ignores
//  an appearance change made while a UI test is running. Not part of CI; the stops are
//  found by their labels and will need updating when a screen changes.
//

import XCTest

@MainActor
final class ScreenWalk: XCTestCase {
    private var app: XCUIApplication!
    private var counter = 0

    private var shotsDir: String {
        ProcessInfo.processInfo.environment["SHOT_DIR"] ?? ""
    }

    private var mode: String {
        ProcessInfo.processInfo.environment["SHOT_MODE"] ?? "unknown"
    }

    private func snap(_ name: String, settle: TimeInterval = 1.0) {
        counter += 1
        Thread.sleep(forTimeInterval: settle)
        let file = String(format: "%02d-%@-%@.png", counter, name, mode)
        let data = XCUIScreen.main.screenshot().pngRepresentation
        do {
            try data.write(to: URL(fileURLWithPath: shotsDir).appending(path: file))
        } catch {
            XCTFail("could not save \(file): \(error)")
        }
    }

    private func tap(_ element: XCUIElement, _ what: String, timeout: TimeInterval = 5) {
        if element.waitForExistence(timeout: timeout) {
            element.tap()
        } else {
            XCTFail("missing: \(what)")
        }
    }

    private func button(_ label: String) -> XCUIElement {
        app.buttons[label].firstMatch
    }

    /// The keyboard key for `label`: the lowest matching button on screen, since the dice
    /// above it can carry the same text.
    private func pressKey(_ label: String) {
        let matches = app.buttons.matching(NSPredicate(format: "label == %@", label)).allElementsBoundByIndex
            .filter { $0.exists && $0.isHittable }
        guard let key = matches.max(by: { $0.frame.minY < $1.frame.minY }) else {
            XCTFail("no key \(label)")
            return
        }
        key.tap()
    }

    /// The leftmost button in a navigation bar on screen: home's bar stays in the tree, offscreen,
    /// while a screen is pushed over it.
    private func back() {
        let visible = app.navigationBars.buttons.allElementsBoundByIndex.filter { $0.exists && $0.isHittable }
        guard let button = visible.min(by: { $0.frame.minX < $1.frame.minX }) else {
            XCTFail("missing: nav back")
            return
        }
        button.tap()
        Thread.sleep(forTimeInterval: 0.8)
    }

    /// The toolbar's overflow menu, where secondary actions go on a phone.
    private func openMenu() {
        tap(app.navigationBars.buttons["More"].firstMatch, "More")
    }

    /// A key with a public half previews it as you type; the others preview behind Show.
    private func makeKey(name: String, kind: String? = nil, hasPublicKey: Bool = false) {
        tap(button("New key"), "New key")
        if let kind {
            tap(app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Kind'")).firstMatch, "Kind picker")
            tap(button(kind), kind)
        }
        let field = app.textFields.firstMatch
        tap(field, "Name field")
        field.typeText(name)
        snap("new-key-\(name)")
        if kind != nil && !hasPublicKey {
            tap(button("Show"), "Show preview")
            snap("new-key-\(name)-shown")
        }
        tap(button("Save"), "Save")
        snap("key-\(name)")
        if hasPublicKey { app.swipeUp() }
        tap(button("Reveal"), "Reveal")
        snap("key-\(name)-revealed")
        if hasPublicKey {
            app.swipeUp()
            snap("key-\(name)-revealed-end")
        }
        back()
    }

    func testWalk() throws {
        try XCTSkipIf(shotsDir.isEmpty, "Set SHOT_DIR (scripts/screen-walk.sh does) to save screenshots.")
        continueAfterFailure = true
        app = XCUIApplication()
        app.launch()
        snap("home-first-launch", settle: 2.5)
        tap(button("Scan your DiceKey"), "Scan your DiceKey")
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        if springboard.alerts.firstMatch.waitForExistence(timeout: 3) {
            snap("scan-camera-permission-alert")
            springboard.alerts.firstMatch.buttons.element(boundBy: 1).tap()
        }
        snap("scan", settle: 2)

        tap(button("Type it in"), "Type it in")
        snap("manual-entry-empty")
        for (index, letter) in "ABCDEFGHIJKLMNOPRSTUVWXYZ".map(String.init).enumerated() {
            let digit = String(index % 6 + 1)
            pressKey(letter)
            if index == 0 { snap("manual-entry-number") }
            pressKey(digit)
            if index == 11 { snap("manual-entry-orientation") }
            let direction = ["upright", "right", "down", "left"][index % 4]
            tap(button("\(letter)\(digit), \(direction)"), "\(letter)\(digit) \(direction)")
            if index == 12 { snap("manual-entry-partial") }
        }
        snap("manual-entry-complete")
        tap(button("Open DiceKey"), "Open DiceKey")
        snap("keep-offer", settle: 1.5)
        tap(app.alerts.buttons["Not now"], "Not now")
        snap("dicekey-new", settle: 1.5)
        tap(button("Show dice"), "Show dice")
        snap("dicekey-dice-shown")

        makeKey(name: "github")
        tap(button("New key"), "New key")
        tap(app.textFields.firstMatch, "Name field")
        app.textFields.firstMatch.typeText("github")
        snap("new-key-existing")
        tap(button("Open it"), "Open it")
        back()
        makeKey(name: "nas", kind: "Passphrase")
        makeKey(name: "cold", kind: "Wallet")
        makeKey(name: "backups", kind: "age", hasPublicKey: true)
        snap("dicekey-with-keys")

        openMenu()
        snap("dicekey-menu")
        tap(button("List card"), "List card")
        snap("list-card-preview", settle: 1.5)
        tap(button("Print"), "Print")
        snap("list-card-print", settle: 2)
        tap(button("Cancel"), "Cancel print")
        tap(button("Done"), "Done list card")
        openMenu()
        tap(button("Recovery sheet"), "Recovery sheet")
        if app.navigationBars["Recovery sheet"].waitForExistence(timeout: 10) {
            snap("recovery-sheet-concealed", settle: 1.5)
            openMenu()
            tap(button("Show"), "Show sheet")
            snap("recovery-sheet-shown", settle: 1.5)
            tap(button("Done"), "Done recovery sheet")
        } else {
            XCTFail("no recovery sheet: scripts/screen-walk.sh enrolls Face ID and matches it")
        }

        app.cells.containing(.staticText, identifier: "nas").firstMatch.swipeLeft()
        snap("key-swiped")
        tap(button("Delete"), "Delete")
        snap("key-delete-confirm")
        tap(button("Delete key"), "Delete key")
        snap("key-deleted-by-swipe")

        tap(app.cells.containing(.staticText, identifier: "github").firstMatch, "github")
        app.swipeUp()
        tap(button("Delete key"), "Delete key on detail")
        snap("key-detail-delete-confirm")
        tap(app.alerts.buttons["Delete key"], "confirm Delete key")
        snap("key-deleted-from-detail", settle: 1.5)
        back()
        snap("home")
    }
}
