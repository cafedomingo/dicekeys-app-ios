//
//  ReferenceScannerComparisonTests.swift
//  ReadDiceKeyTests
//
//  Compares the Swift scanner's per-face output with Fixtures/reference-cpp-scanner.json,
//  the output of the vendored C++ scanner (real OpenCV) over the same corpus. Where the
//  corpus test only says "the key was misread", this says which stage diverged:
//
//    * an undoverline code or a missing undoverline  -> rectangle detection / bit sampling
//    * a line endpoint or centre off by pixels        -> minAreaRect, RRectCorners or line trimming
//    * a different orientation                        -> grid fitting
//    * a different first OCR character                -> the crop (warpAffine) or the OCR
//
//  The reference was decoded by OpenCV's libjpeg, this test decodes with ImageIO, so a few
//  pixels differ per photo; the tolerances absorb that. Second OCR choices are not compared
//  (they flip on such differences).
//

import CoreGraphics
import Foundation
import Testing
@testable import ReadDiceKey

struct ReferenceScan: Decodable, Sendable {
    let file: String
    let complete: Bool
    let humanReadable: String
    let totalError: Int
    let faces: [ScannedFace]?

    /// Photos with a known answer. On the crash-only / not-yet-readable photos both
    /// scanners emit noise, and noise is sensitive to JPEG decoder differences (ImageIO
    /// here, libjpeg for the reference), so comparing it face by face is meaningless.
    static let all: [ReferenceScan] = {
        let url = Bundle.module.resourceURL!.appendingPathComponent("Fixtures/reference-cpp-scanner.json")
        guard let data = try? Data(contentsOf: url) else { return [] }
        let scans = (try? JSONDecoder().decode([ReferenceScan].self, from: data)) ?? []
        return scans.filter { scan in
            let base = (scan.file as NSString).deletingPathExtension
            let suffix = String(base.dropFirst(75))
            return !CorpusImage.crashOnlyPrefixes.contains { base.hasPrefix($0) }
                && !CorpusImage.crashOnlySuffixes.contains { suffix == $0 }
        }
    }()
}

extension ReferenceScan: CustomTestStringConvertible {
    var testDescription: String { file }
}

@Suite("Swift scanner against the C++ reference output")
struct ReferenceScannerComparisonTests {
    /// Pixels an undoverline endpoint may differ by. When two candidate rectangles have
    /// exactly the same minimum area, OpenCV's rotating calipers and this port can pick
    /// different ones, which moves a line end by a few pixels (up to 6.4 on the corpus when
    /// both read the same decoded bytes); JPEG decoder differences add a little more.
    static let endpointTolerance = 10.0
    /// Pixels a face centre may differ by (the same effect, averaged over two lines).
    static let centerTolerance = 4.0

    @Test("reference fixture is present")
    func fixturePresent() {
        #expect(ReferenceScan.all.count >= 17)
    }

    @Test("matches the C++ scanner face by face", arguments: ReferenceScan.all)
    func matchesReference(reference: ReferenceScan) throws {
        let url = Bundle.module.resourceURL!.appendingPathComponent("Fixtures/images/\(reference.file)")
        let (rgba, width, height) = try Corpus.rgba(from: url)
        let scanner = DiceKeyScanner()
        scanner.process(rgba: rgba, width: width, height: height)
        let json = scanner.readResultJSON

        guard let referenceFaces = reference.faces else {
            // The C++ found no grid in this photo; nothing to compare face by face.
            #expect(!json.isEmpty)
            return
        }
        let decoded = try JSONDecoder().decode([ScannedFace].self, from: Data(json.utf8))
        try #require(decoded.count == 25, "Swift scanner read \(decoded.count) faces where the C++ read 25 (grid fitting)")

        // A DiceKey read is rotation-independent: when the grid's angle is near a 45°
        // boundary the two implementations can index the faces from different corners.
        // Compare against the rotation of our read that best matches the reference.
        let candidates = (0..<4).reduce(into: [decoded]) { acc, _ in acc.append(Self.rotated(acc.last!)) }
        let problemsPerCandidate = candidates.map { Self.problems(ours: $0, reference: referenceFaces) }
        let problems = problemsPerCandidate.min { $0.count < $1.count } ?? []

        // Photos upstream reads with a small error budget may flip a bit or two under a
        // different JPEG decoder; allow that many faces to differ on those photos only.
        let allowedFaces = Self.allowedDifferingFaces(for: reference.file)
        let differingFaces = Set(problems.compactMap { $0.split(separator: ":").first })
        #expect(differingFaces.count <= allowedFaces, Comment(rawValue: "\(reference.file):\n" + problems.joined(separator: "\n")))
    }

    static func allowedDifferingFaces(for file: String) -> Int {
        let base = (file as NSString).deletingPathExtension
        let suffix = String(base.dropFirst(75))
        return CorpusImage.allowedErrorsByPrefix.first { base.hasPrefix($0.key) }?.value
            ?? CorpusImage.allowedErrorsBySuffix[suffix] ?? 0
    }

    /// Rotates a read one quarter turn clockwise: faces re-index by the 5x5 rotation and
    /// each face's orientation letter advances. Image-space coordinates are unchanged.
    static func rotated(_ faces: [ScannedFace]) -> [ScannedFace] {
        Corpus.rotationIndexes.map { i in
            var face = faces[i]
            face.orientationAsLowercaseLetterTrbl = face.orientation.map { String(Corpus.rotateOrientation($0)) }
            return face
        }
    }

    static func problems(ours faces: [ScannedFace], reference referenceFaces: [ScannedFace]) -> [String] {
        var problems: [String] = []
        for (i, (face, ref)) in zip(faces, referenceFaces).enumerated() {
            func check(_ ours: ScannedFace.Undoverline?, _ theirs: ScannedFace.Undoverline?, _ name: String) {
                switch (ours, theirs) {
                case (nil, nil):
                    break
                case (nil, .some):
                    problems.append("face \(i): \(name) missing (C++ read code \(theirs!.code))")
                case (.some, nil):
                    problems.append("face \(i): \(name) read where the C++ found none")
                case let (.some(a), .some(b)):
                    if a.code != b.code {
                        problems.append("face \(i): \(name) code \(a.code) vs C++ \(b.code)")
                    }
                    let d1 = hypot(a.line.start.x - b.line.start.x, a.line.start.y - b.line.start.y)
                    let d2 = hypot(a.line.end.x - b.line.end.x, a.line.end.y - b.line.end.y)
                    if max(d1, d2) > Self.endpointTolerance {
                        problems.append("face \(i): \(name) endpoints off by \(String(format: "%.1f", max(d1, d2))) px")
                    }
                }
            }
            check(face.underline, ref.underline, "underline")
            check(face.overline, ref.overline, "overline")
            let dc = hypot(face.center.x - ref.center.x, face.center.y - ref.center.y)
            if dc > Self.centerTolerance {
                problems.append("face \(i): center off by \(String(format: "%.1f", dc)) px")
            }
            // The C++ writes "?" for an unknown orientation; the Swift scanner writes null.
            let refOrientation: Character? = ref.orientation == "?" ? nil : ref.orientation
            if face.orientation != refOrientation {
                problems.append("face \(i): orientation \(face.orientation.map(String.init) ?? "nil") vs C++ \(refOrientation.map(String.init) ?? "nil")")
            }
            if face.letter != ref.letter || face.digit != ref.digit {
                problems.append("face \(i): OCR \(face.ocrLetterCharsFromMostToLeastLikely)/\(face.ocrDigitCharsFromMostToLeastLikely) vs C++ \(ref.ocrLetterCharsFromMostToLeastLikely)/\(ref.ocrDigitCharsFromMostToLeastLikely)")
            }
        }
        return problems
    }
}
