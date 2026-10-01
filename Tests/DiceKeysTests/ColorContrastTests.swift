//
//  ColorContrastTests.swift
//  DiceKeysTests
//
//  The palette's promises, measured: WCAG 2 contrast of 4.5:1 for text and 3:1 for the edge
//  that separates the navy DiceKey from a dark background. Backgrounds are resolved from the
//  system colors, so a change in iOS shows up here. System
//  references are checked by resolving them, because actool accepts any reference name.
//

import Foundation
import Testing
import UIKit

@testable import DiceKeys

@MainActor
struct ColorContrastTests {
    private struct RGBA { var r, g, b, a: Double }

    private static func traits(_ style: UIUserInterfaceStyle, _ level: UIUserInterfaceLevel) -> UITraitCollection {
        UITraitCollection {
            $0.userInterfaceStyle = style
            $0.userInterfaceLevel = level
        }
    }

    private static func rgba(_ color: UIColor, _ style: UIUserInterfaceStyle, _ level: UIUserInterfaceLevel = .base)
        -> RGBA
    {
        var r: CGFloat = 0
        var g: CGFloat = 0
        var b: CGFloat = 0
        var a: CGFloat = 0
        color.resolvedColor(with: traits(style, level)).getRed(&r, green: &g, blue: &b, alpha: &a)
        return RGBA(r: r, g: g, b: b, a: a)
    }

    /// Source-over compositing onto an opaque background.
    private static func over(_ fg: RGBA, _ bg: RGBA) -> RGBA {
        RGBA(
            r: fg.r * fg.a + bg.r * (1 - fg.a), g: fg.g * fg.a + bg.g * (1 - fg.a), b: fg.b * fg.a + bg.b * (1 - fg.a),
            a: 1)
    }

    private static func luminance(_ c: RGBA) -> Double {
        func linear(_ v: Double) -> Double { v <= 0.04045 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4) }
        return 0.2126 * linear(c.r) + 0.7152 * linear(c.g) + 0.0722 * linear(c.b)
    }

    private static func contrast(_ a: RGBA, _ b: RGBA) -> Double {
        let (la, lb) = (luminance(a), luminance(b))
        return (max(la, lb) + 0.05) / (min(la, lb) + 0.05)
    }

    private static let styles: [UIUserInterfaceStyle] = [.light, .dark]

    /// Text needs 4.5:1 on the screen's own backgrounds. On the raised surfaces of sheets and
    /// menus the accent is held to 3:1, the same compromise as the system blue there.
    @Test("the accent reads as text")
    func accentAsText() {
        for style in Self.styles {
            let accent = Self.rgba(.accent, style)
            for background in [UIColor.systemBackground, .systemGroupedBackground, .secondarySystemBackground] {
                #expect(
                    Self.contrast(accent, Self.rgba(background, style)) >= 4.5, "\(background) in \(style.rawValue)")
            }
            for background in [UIColor.secondarySystemBackground, .tertiarySystemBackground] {
                #expect(
                    Self.contrast(accent, Self.rgba(background, style, .elevated)) >= 3,
                    "elevated \(background) in \(style.rawValue)")
            }
        }
    }

    @Test("labels on filled colors read")
    func labelsOnFills() {
        for style in Self.styles {
            // Filled buttons draw the system's white label; their titles are large text, so 3:1.
            let white = RGBA(r: 1, g: 1, b: 1, a: 1)
            #expect(Self.contrast(white, Self.rgba(.accent, style)) >= 3, "button label in \(style.rawValue)")
            #expect(
                Self.contrast(Self.rgba(.Interface.onWarning, style), Self.rgba(.Interface.warningBackground, style))
                    >= 4.5)
            let bg = Self.rgba(.systemBackground, style)
            let key = Self.over(Self.rgba(.Interface.keyBackground, style), bg)
            #expect(Self.contrast(Self.rgba(.label, style), key) >= 4.5, "key label, \(style.rawValue)")
        }
    }

    @Test("the edge separates the navy box from a dark background, and is invisible in light")
    func objectEdge() {
        #expect(Self.rgba(.Interface.objectEdge, .light).a == 0)
        let edge = Self.rgba(.Interface.objectEdge, .dark)
        let box = Self.rgba(.Depiction.diceBox, .dark)
        // Navy DiceKeys are drawn only on screen backgrounds. The one in the save sheet, on an
        // elevated surface where this edge is fainter, is drawn in kitBlue, which reads on its own.
        let screens = [
            ("systemBackground", Self.rgba(.systemBackground, .dark)),
            ("systemGroupedBackground", Self.rgba(.systemGroupedBackground, .dark))
        ]
        // The 3:1 that matters is against the background: that is the object's boundary. Against
        // the box the edge only has to read as a rim, and a brighter one would outshine the dice.
        for (name, bg) in screens {
            #expect(Self.contrast(Self.over(edge, bg), bg) >= 3, "edge on \(name)")
            #expect(Self.contrast(Self.over(edge, bg), box) >= 2, "edge against the box on \(name)")
        }
    }

    @Test("system references resolve to the intended system colors")
    func systemReferences() {
        let pairs: [(String, UIColor, UIColor)] = [
            ("errorText", .Interface.errorText, .systemRed),
            ("successText", .Interface.successText, .systemGreen),
            ("keyBackground", .Interface.keyBackground, .secondarySystemFill)
        ]
        for style in Self.styles {
            for (name, ours, system) in pairs {
                let (a, b) = (Self.rgba(ours, style), Self.rgba(system, style))
                #expect(
                    abs(a.r - b.r) < 0.002 && abs(a.g - b.g) < 0.002 && abs(a.b - b.b) < 0.002
                        && abs(a.a - b.a) < 0.002,
                    "\(name) does not resolve to its system color in \(style.rawValue)")
            }
        }
    }

    @Test("the camera backdrop is the same black in both appearances")
    func cameraBackdropIsFixed() {
        let (light, dark) = (Self.rgba(.Camera.backdrop, .light), Self.rgba(.Camera.backdrop, .dark))
        #expect(light.r == 0 && light.g == 0 && light.b == 0 && light.a == 1)
        #expect(dark.r == 0 && dark.g == 0 && dark.b == 0 && dark.a == 1)
    }

    @Test("the privacy cover keeps its colors in both appearances")
    func privacyCoverColors() {
        func bytes(_ c: UIColor, _ s: UIUserInterfaceStyle) -> [Int] {
            let v = Self.rgba(c, s)
            return [v.r, v.g, v.b].map { Int(($0 * 255).rounded()) }
        }
        #expect(bytes(.Brand.coverHighlight, .light) == [99, 116, 204])
        #expect(bytes(.Brand.coverBody, .light) == [52, 65, 141])
        #expect(bytes(.Brand.coverShadow, .light) == [22, 28, 72])
        #expect(bytes(.Brand.coverHighlight, .dark) == [52, 65, 141])
        #expect(bytes(.Brand.coverBody, .dark) == [22, 28, 72])
        #expect(bytes(.Brand.coverShadow, .dark) == [10, 12, 34])
    }
}
