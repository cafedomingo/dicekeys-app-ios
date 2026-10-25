//
//  ScannedCodeTests.swift
//  DiceKeyVaultTests
//

import Foundation
import Testing

@testable import DiceKeyVault

@MainActor
struct ScannedCodeTests {
    @Test("a list link reads as a list, a recovery code as a recovery")
    func reads() throws {
        #expect(try ScannedCode(payload: Fixture.text("catalog-link-v2.txt")) == .list(PaperFormatV2Tests.expected))
        guard case .recovery(let code)? = try ScannedCode(payload: Fixture.text("recovery-v2.txt")) else {
            Issue.record("not read as a recovery code")
            return
        }
        #expect(code.diceKey == DiceKey.example)
    }

    @Test("someone else's code is ignored")
    func foreignCodesAreIgnored() throws {
        for payload in ["https://example.com", "WIFI:S:home;T:WPA;P:x;;", "hello", "otherapp://import?catalog=e30"] {
            #expect(try ScannedCode(payload: payload) == nil)
        }
    }

    @Test("this app's code that can't be read is refused, not ignored")
    func brokenOwnCodesThrow() {
        #expect(throws: CatalogFile.Failure.notACatalog) {
            try ScannedCode(payload: "dicekeyvault://import?catalog=%21")
        }
        #expect(throws: CatalogFile.Failure.notACatalog) { try ScannedCode(payload: "DKVR:!!") }
    }

    @Test("a code from a newer version says to update the app")
    func newerVersionSaysToUpdate() {
        let message = CatalogFile.Failure.newerVersion(3).localizedDescription
        #expect(message.contains("newer version"))
    }

    @Test("only this app's codes count as its own")
    func ownCodes() throws {
        #expect(ScannedCode.isOwn(try Fixture.text("catalog-link-v2.txt")))
        #expect(ScannedCode.isOwn(try Fixture.text("recovery-v2.txt")))
        #expect(!ScannedCode.isOwn("https://example.com"))
    }
}
