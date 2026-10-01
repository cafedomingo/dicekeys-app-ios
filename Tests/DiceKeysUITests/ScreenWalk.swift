//
//  ScreenWalk.swift
//  DiceKeysUITests
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

    /// The tab bar button, or the plain button that stands in for it when the bar is minimized.
    private func selectTab(_ label: String) {
        let tab = app.tabBars.buttons[label].firstMatch
        tap(tab.exists ? tab : button(label), "\(label) tab")
    }

    private func back() {
        tap(app.navigationBars.buttons.element(boundBy: 0), "nav back")
        Thread.sleep(forTimeInterval: 0.8)
    }

    func testWalk() throws {
        try XCTSkipIf(shotsDir.isEmpty, "Set SHOT_DIR (scripts/screen-walk.sh does) to save screenshots.")
        continueAfterFailure = true
        app = XCUIApplication()
        app.launch()
        snap("home-empty", settle: 2)

        // Scan (no camera in the Simulator)
        tap(app.staticTexts["Load your DiceKey"], "Load your DiceKey")
        Thread.sleep(forTimeInterval: 2)
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        if springboard.alerts.firstMatch.waitForExistence(timeout: 2) {
            snap("scan-camera-permission-alert")
            let alert = springboard.alerts.firstMatch
            if alert.buttons["Allow"].exists { alert.buttons["Allow"].tap() } else { alert.buttons.element(boundBy: 0).tap() }
            Thread.sleep(forTimeInterval: 1.5)
        }
        snap("scan")

        // Manual entry
        tap(button("Enter the DiceKey by Hand"), "Enter by hand")
        snap("manual-entry-empty", settle: 1)

        let letters = "ABCDEFGHIJKLMNOPRSTUVWXYZ".map(String.init)
        for (index, letter) in letters.enumerated() {
            pressKey(letter)
            pressKey(String(index % 6 + 1))
            if index == 11 {
                snap("manual-entry-partial")
            }
        }
        snap("manual-entry-complete")
        tap(button("Done"), "Done manual")
        Thread.sleep(forTimeInterval: 1.5)

        // DiceKey screen
        snap("dicekey")
        tap(button("Hide Dice"), "Hide Dice")
        snap("dicekey-hidden-dice")
        tap(button("Show Dice"), "Show Dice")

        // Save sheet
        tap(button("Save"), "Save toolbar")
        snap("save-sheet", settle: 1)
        let toggle = app.switches.firstMatch
        if toggle.waitForExistence(timeout: 3) {
            (toggle.switches.firstMatch.exists ? toggle.switches.firstMatch : toggle).tap()
            Thread.sleep(forTimeInterval: 2)
            if app.alerts.firstMatch.exists {
                snap("save-sheet-error-alert")
                app.alerts.firstMatch.buttons.firstMatch.tap()
            } else {
                snap("save-sheet-saved")
            }
        }
        tap(app.navigationBars["Save DiceKey"].buttons["Done"], "Save sheet Done")
        Thread.sleep(forTimeInterval: 1)

        // Secrets
        selectTab("Secrets")
        snap("recipes", settle: 1)
        app.swipeUp()
        snap("recipes-scrolled", settle: 1)
        app.swipeDown()
        Thread.sleep(forTimeInterval: 1)

        // Derived value: password template
        tap(button("1Password"), "1Password")
        snap("derived-password", settle: 1.5)
        let picker = app.buttons.matching(NSPredicate(format: "label CONTAINS 'Password' OR label CONTAINS 'JSON'")).allElementsBoundByIndex
            .first { $0.frame.minY > 300 && $0.label != "Copy Password" }
        if let picker {
            picker.tap()
            snap("derived-format-menu", settle: 1)
            app.tap()
            Thread.sleep(forTimeInterval: 0.5)
            if app.collectionViews.firstMatch.exists || app.otherElements["Output Format"].exists {
                app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.1)).tap()
            }
        }
        tap(button("Show QR code"), "QR button")
        snap("qr-usage-question", settle: 1)
        tap(button("The camera app on an iPhone or iPad"), "iPhone camera")
        snap("qr-ios-warning", settle: 0.8)
        tap(button("Got it. I'll be careful"), "Got it")
        snap("qr-code", settle: 0.8)
        tap(button("OK"), "QR OK")
        Thread.sleep(forTimeInterval: 1)
        back()

        // Derived value: secret (BIP39) template
        app.swipeUp()
        Thread.sleep(forTimeInterval: 0.8)
        tap(button("Cryptocurrency wallet seed"), "wallet seed")
        snap("derived-secret", settle: 1.5)
        back()
        tap(button("SSH"), "SSH")
        snap("derived-signing-key", settle: 1.5)
        back()

        // Custom recipe sheet
        app.swipeUp()
        Thread.sleep(forTimeInterval: 0.8)
        tap(button("Password"), "Custom Password")
        snap("custom-recipe-purpose", settle: 1.2)
        tap(button("Raw JSON"), "Raw JSON segment")
        snap("custom-recipe-raw-json-alert", settle: 1)
        tap(app.alerts.buttons["I accept the risk"], "accept risk")
        snap("custom-recipe-raw-json", settle: 0.8)
        tap(button("Purpose"), "Purpose segment")
        let purposeField = app.textFields["purpose"]
        tap(purposeField, "purpose field")
        purposeField.typeText("dicekeys.org")
        snap("custom-recipe-filled-keyboard", settle: 0.8)
        tap(app.navigationBars.buttons["Done"], "custom Done")
        snap("derived-custom-recipe", settle: 1.5)
        tap(button("Save recipe in the menu"), "Save recipe")
        Thread.sleep(forTimeInterval: 0.6)
        back()
        app.swipeDown()
        snap("recipes-with-saved", settle: 0.8)

        // Backup: Stickeys
        selectTab("Backup")
        snap("backup-choose", settle: 1)
        tap(app.staticTexts["Use a Stickeys Kit"], "Stickeys")
        snap("backup-stickeys-intro", settle: 1)
        tap(button("Next"), "Next")
        snap("backup-stickeys-step-first-die", settle: 1)
        for _ in 0..<12 { button("Next").tap() }
        snap("backup-stickeys-step-center-die", settle: 1)
        tap(button("Skip to the end"), "Skip to end")
        snap("backup-stickeys-validate", settle: 1)
        tap(button("Let me skip this step"), "skip validation")
        snap("backup-validate-skipped", settle: 0.8)

        // Backup: DiceKey kit
        tap(button("Back to the start"), "Back to start")
        Thread.sleep(forTimeInterval: 0.6)
        tap(button("Previous"), "Previous")
        Thread.sleep(forTimeInterval: 1)
        tap(app.staticTexts["Use a DiceKey Kit"], "DiceKey kit")
        snap("backup-dicekey-intro", settle: 1)
        tap(button("Next"), "Next")
        snap("backup-dicekey-step-first-die", settle: 1)
        tap(button("Skip to the end"), "Skip to end")
        snap("backup-dicekey-validate", settle: 1)

        // Home with a DiceKey in memory
        selectTab("DiceKey")
        Thread.sleep(forTimeInterval: 0.6)
        back()
        snap("home-with-dicekey", settle: 1)
        let menu = app.buttons.matching(NSPredicate(format: "label CONTAINS 'ellipsis' OR label CONTAINS 'More' OR label CONTAINS 'in memory' OR label CONTAINS 'ing in' OR label CONTAINS 'until'")).firstMatch
        if menu.waitForExistence(timeout: 2) {
            menu.tap()
            snap("home-dicekey-menu", settle: 1)
            let lock = app.buttons.matching(NSPredicate(format: "label CONTAINS 'Immediately'")).firstMatch
            if lock.exists {
                lock.tap()
                snap("home-after-lock", settle: 1.5)
            }
        } else {
            XCTFail("missing: home DiceKey menu")
        }

        // Assembly
        let assemble = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Assemble'")).firstMatch
        tap(assemble, "Assemble")
        snap("assembly-1-randomize", settle: 1.2)
        tap(button("Next"), "Next")
        snap("assembly-2-drop-dice", settle: 0.8)
        tap(button("Next"), "Next")
        snap("assembly-3-fill-slots", settle: 0.8)
        tap(button("Next"), "Next")
        snap("assembly-4-scan", settle: 0.8)
        tap(button("Let me skip this step"), "skip scan")
        tap(button("Next"), "Next")
        snap("assembly-5-backup-choose", settle: 0.8)
        tap(button("Let me skip this step"), "skip backup")
        snap("assembly-6-seal-box", settle: 0.8)
        tap(button("Next"), "Next")
        snap("assembly-7-done", settle: 0.8)
    }
}
