//
//  ScannerBenchmarkTests.swift
//  ReadDiceKeyTests
//
//  Opt-in timing and memory of `DiceKeyScanner.scan` on a camera-sized frame. Skipped
//  unless SCANNER_BENCHMARK is set, so CI stays fast; run it on its own, since the peak
//  memory figure is for the whole test process:
//
//      SCANNER_BENCHMARK=1 swift test -c release --filter ScannerBenchmark
//
//  The app scans the centered square of a 1920x1080 session, so the frame here is a corpus
//  photo scaled to 1080x1080. The first scan warms up the allocator; the median of the rest
//  is the number to compare against docs/SCANNING.md.
//

import Darwin
import Foundation
import Testing
@testable import ReadDiceKey

@Suite("Scanner benchmark (opt-in)", .enabled(if: ProcessInfo.processInfo.environment["SCANNER_BENCHMARK"] != nil))
struct ScannerBenchmarkTests {
    @Test("time and memory per 1080x1080 frame")
    func timeAndMemoryPerFrame() throws {
        let url = try #require(CorpusImage.all.first { $0.url.lastPathComponent.hasPrefix("K13Y63A23") && !$0.url.lastPathComponent.contains("glare") }?.url)
        let frame = try Corpus.gray(from: url, square: 1080)
        let peakBefore = peakFootprint()
        var samples: [Duration] = []
        for _ in 0..<21 {
            // A fresh scanner each time, so every frame does the full work.
            var scanner = DiceKeyScanner()
            samples.append(ContinuousClock().measure { scanner.scan(frame) })
        }
        let peakAfter = peakFootprint()
        let sorted = samples.dropFirst().sorted()
        let ms = { (d: Duration) in Double(d.components.seconds) * 1000 + Double(d.components.attoseconds) / 1e15 }
        print(String(format: "scanner benchmark: 1080x1080 frame, median %.1f ms, min %.1f ms, max %.1f ms; scanning raised peak memory by %.1f MB",
                     ms(sorted[sorted.count / 2]), ms(sorted.first!), ms(sorted.last!), Double(peakAfter - peakBefore) / 1e6))
        #expect(sorted[sorted.count / 2] < .seconds(2))
    }

    /// The process's peak physical footprint, the figure Xcode's memory gauge and jetsam use.
    private func peakFootprint() -> UInt64 {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count) }
        }
        return result == KERN_SUCCESS ? UInt64(info.ledger_phys_footprint_peak) : 0
    }
}
