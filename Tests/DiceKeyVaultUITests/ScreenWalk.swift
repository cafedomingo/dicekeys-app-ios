//
//  ScreenWalk.swift
//  DiceKeyVaultUITests
//
//  Walks every screen the Simulator can reach and saves a screenshot at each stop, so a
//  visual change can be judged screen by screen in both appearances and, on an iPad, both
//  orientations. Run it with scripts/screen-walk.sh, which sets the appearance before each run:
//  the Simulator ignores an appearance change made while a UI test is running. Not part of CI;
//  the stops are found by their labels and will need updating when a screen changes.
//

import UIKit
import XCTest

@MainActor
final class ScreenWalk: XCTestCase {
    private enum Orientation: String {
        case portrait
        case landscape

        var device: UIDeviceOrientation { self == .landscape ? .landscapeLeft : .portrait }
    }

    /// The most swipes up `tap` spends looking for an element below the fold.
    private static let maxScrolls = 5
    private static let rowScrollLimit = 3

    private var app: XCUIApplication!
    private var counter = 0

    private var shotsDir: String {
        ProcessInfo.processInfo.environment["SHOT_DIR"] ?? ""
    }

    private var mode: String {
        ProcessInfo.processInfo.environment["SHOT_MODE"] ?? "unknown"
    }

    private var orientation: Orientation {
        ProcessInfo.processInfo.environment["SHOT_ORIENTATION"].flatMap(Orientation.init) ?? .portrait
    }

    /// The suffix of every shot's name: the appearance, after the orientation unless it is
    /// portrait, so portrait names stay as they were and the two orientations never collide.
    private var variant: String {
        orientation == .portrait ? mode : "\(orientation.rawValue)-\(mode)"
    }

    /// In landscape the screenshot is still the device's portrait bitmap, a quarter turn
    /// clockwise from what the window shows.
    private func uprightPNG(_ screenshot: XCUIScreenshot) -> Data {
        guard orientation == .landscape else { return screenshot.pngRepresentation }
        let image = screenshot.image
        let turned = UIImage(cgImage: image.cgImage!, scale: image.scale, orientation: .left)
        let format = UIGraphicsImageRendererFormat()
        format.scale = image.scale
        return UIGraphicsImageRenderer(size: turned.size, format: format).pngData { _ in turned.draw(at: .zero) }
    }

    private func snap(_ name: String, settle: TimeInterval = 1.0) {
        counter += 1
        Thread.sleep(forTimeInterval: settle)
        let file = String(format: "%02d-%@-%@.png", counter, name, variant)
        let data = uprightPNG(XCUIScreen.main.screenshot())
        do {
            try data.write(to: URL(fileURLWithPath: shotsDir).appending(path: file))
        } catch {
            XCTFail("could not save \(file): \(error)")
        }
    }

    /// Swipes up over the detail's list, the last in the tree: `app.swipeUp()` didn't scroll the
    /// capped detail on an iPad in landscape. Not `isHittable`: the key screen reports false for
    /// it while it is plainly on screen.
    private func swipeUpDetail() {
        (app.collectionViews.allElementsBoundByIndex.last { $0.exists } ?? app).swipeUp()
    }

    /// Swipes up until `element` exists. A list leaves rows below the fold out of the
    /// accessibility tree until it scrolls, and a window as short as an iPad's in landscape
    /// leaves more of them there than portrait does.
    private func scrollUntilExists(_ element: XCUIElement) -> Bool {
        for _ in 0..<Self.maxScrolls where !element.exists { swipeUpDetail() }
        return element.exists
    }

    /// XCTest's first existence check comes about 1 s after `waitForExistence` is called, even
    /// when the element is already there, so `exists` is tried first.
    private func tap(_ element: XCUIElement, _ what: String, timeout: TimeInterval = 5) {
        if element.exists || element.waitForExistence(timeout: timeout) || scrollUntilExists(element) {
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

    /// The back button on screen, wherever the system puts it: on iPhone Duo, in a toolbar
    /// beside the content rather than a navigation bar. Offscreen bars stay in the tree. With
    /// the sidebar beside the detail, home is already on screen and the detail's root has no
    /// back button, so a step that only goes home passes `isRequired: false`.
    private func back(isRequired: Bool = true) {
        let backButtons = app.buttons.matching(identifier: "BackButton").allElementsBoundByIndex
        guard let button = backButtons.first(where: { $0.exists && $0.isHittable }) else {
            if isRequired { XCTFail("missing: nav back") }
            return
        }
        button.tap()
        Thread.sleep(forTimeInterval: 0.8)
    }

    /// The detail's New key button, since the sidebar has a New key row of its own.
    private var newKeyButton: XCUIElement {
        rightmost(app.buttons.matching(identifier: "New key"))
    }

    /// The toolbar's overflow menu, where secondary actions go on a phone.
    private func openMenu() {
        tap(button("More"), "More")
    }

    /// The match furthest right that is on screen, else the first match. Beside a sidebar, the
    /// detail's copy of a row or button is the one on the right, and it pushes where the
    /// sidebar's selects; a phone shows only one copy.
    private func rightmost(_ matches: XCUIElementQuery) -> XCUIElement {
        matches.allElementsBoundByIndex
            .filter { $0.exists && $0.isHittable }
            .max { $0.frame.minX < $1.frame.minX } ?? matches.firstMatch
    }

    /// A list row by its text, scrolled until all of it is in the window. A row below the fold is
    /// absent from the accessibility tree on a window too short for the list, and present but
    /// mostly off screen when it only just misses; `isHittable` is true for a sliver of it.
    private func row(containing text: String) -> XCUIElement {
        let row = app.cells.containing(.staticText, identifier: text).firstMatch
        let window = app.windows.firstMatch
        for _ in 0..<Self.rowScrollLimit where !(row.exists && window.frame.contains(row.frame)) {
            app.swipeUp()
        }
        return row
    }

    /// A key with a public half previews it as you type; the others preview behind Show.
    private func makeKey(name: String, kind: String? = nil, hasPublicKey: Bool = false) {
        tap(newKeyButton, "New key")
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
        if hasPublicKey { swipeUpDetail() }
        tap(button("Reveal"), "Reveal")
        snap("key-\(name)-revealed")
        if hasPublicKey {
            swipeUpDetail()
            snap("key-\(name)-revealed-end")
        }
        back()
    }

    func testWalk() throws {
        try XCTSkipIf(shotsDir.isEmpty, "Set SHOT_DIR (scripts/screen-walk.sh does) to save screenshots.")
        continueAfterFailure = true
        XCUIDevice.shared.orientation = orientation.device
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
        tap(rightmost(app.cells.containing(.staticText, identifier: "Default")), "Default key")
        snap("key-default")
        back()
        tap(button("Show dice"), "Show dice")
        snap("dicekey-dice-shown")

        makeKey(name: "github")
        tap(newKeyButton, "New key")
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

        row(containing: "nas").swipeLeft()
        snap("key-swiped")
        tap(button("Delete"), "Delete")
        snap("key-delete-confirm")
        tap(button("Delete key"), "Delete key")
        snap("key-deleted-by-swipe")

        tap(rightmost(app.cells.containing(.staticText, identifier: "github")), "github")
        swipeUpDetail()
        tap(button("Delete key"), "Delete key on detail")
        snap("key-detail-delete-confirm")
        tap(app.alerts.buttons["Delete key"], "confirm Delete key")
        snap("key-deleted-from-detail", settle: 1.5)
        back(isRequired: false)
        snap("home")
    }
}
