//
//  UpstreamCompareTests.swift
//  ReadDiceKeyTests
//
//  The half of scripts/compare-upstream/compare-upstream.sh that runs this scanner. Skipped
//  unless UPSTREAM_COMPARE_DIR names a directory to write to. Into it go the gray pixels of
//  every photo at each corpus size and of every frame of the video, as PGMs, so that upstream's
//  scanner reads the very bytes this one does, and this scanner's reads of them as TSVs.
//

import Foundation
import Testing

@testable import ReadDiceKey

private let outputDirectory = ProcessInfo.processInfo.environment["UPSTREAM_COMPARE_DIR"].map { URL(filePath: $0) }

@Suite("Upstream comparison (opt-in)", .serialized, .enabled(if: outputDirectory != nil))
struct UpstreamCompareTests {
    @Test("writes each photo's gray pixels at each size, and this scanner's single-frame reads of them")
    func photos() throws {
        let directory = try #require(outputDirectory)
        var rows = ["pgm\tfolder\tfile\tsize\tms\tfaces\tright\twrong"]
        for image in CorpusImage.all {
            let folder = image.url.deletingLastPathComponent().lastPathComponent
            for size in Corpus.Size.allCases {
                let gray = try Corpus.gray(from: image.url, size: size)
                let pgm = directory.appending(
                    path: "photos/\(size.rawValue)/\(folder)/\(image.url.lastPathComponent).pgm")
                try gray.write(toPGM: pgm)
                var scanner = DiceKeyScanner()
                let elapsed = ContinuousClock().measure { scanner.scan(gray) }
                let score = image.expected.map { Corpus.score(scanner.faces, against: $0) }
                rows.append(
                    [
                        pgm.path, folder, image.url.lastPathComponent, size.rawValue, "\(elapsed / .milliseconds(1))",
                        name(of: scanner.faces), score.map { "\($0.right)" } ?? "", score.map { "\($0.wrong)" } ?? ""
                    ].joined(separator: "\t"))
            }
        }
        try (rows.joined(separator: "\n") + "\n").write(
            to: directory.appending(path: "repo-photos.tsv"), atomically: true, encoding: .utf8)
    }

    /// The corpus has one video, which upstream's scanner reads as one stream too.
    @Test("writes the video's frames, and this scanner's reads of them merged and one at a time")
    func video() async throws {
        let directory = try #require(outputDirectory)
        #expect(ScannerCorpusTests.videos.count == 1)
        let url = try #require(ScannerCorpusTests.videos.first)
        var merged = DiceKeyScanner()
        var rows = ["pgm\tvideo\tframe\tmerged\tsingle"]
        for (index, frame) in try await Corpus.frames(of: url).enumerated() {
            let pgm = directory.appending(path: "video/\(String(format: "%04d", index)).pgm")
            try frame.write(toPGM: pgm)
            merged.scan(frame)
            var single = DiceKeyScanner()
            single.scan(frame)
            rows.append(
                [pgm.path, url.lastPathComponent, "\(index)", name(of: merged.faces), name(of: single.faces)]
                    .joined(separator: "\t"))
        }
        try (rows.joined(separator: "\n") + "\n").write(
            to: directory.appending(path: "repo-video.tsv"), atomically: true, encoding: .utf8)
    }
}

/// The faces as a file name gives them: letter, digit and clockwise turns, "---" for no face.
private func name(of faces: [ScannedFace?]) -> String {
    faces.map { $0.map { "\($0.letter.rawValue)\($0.digit.rawValue)\($0.clockwiseTurns)" } ?? "---" }.joined()
}

extension GrayImage {
    /// A binary PGM: the header `P5`, the size and the maximum value, then one byte per pixel.
    fileprivate func write(toPGM url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try (Data("P5\n\(width) \(height)\n\(UInt8.max)\n".utf8) + Data(pixels)).write(to: url)
    }
}
