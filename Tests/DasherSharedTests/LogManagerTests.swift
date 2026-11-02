import XCTest
@testable import DasherShared

final class LogManagerTests: XCTestCase {
    private var tempDir: URL!
    private var savedAdvancedLogging: Bool = false

    override func setUpWithError() throws {
        try super.setUpWithError()
        savedAdvancedLogging = LogManager.advancedLogging
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("DasherLogTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        LogManager.setAdvancedLogging(false)
    }

    override func tearDownWithError() throws {
        LogManager.setAdvancedLogging(savedAdvancedLogging)
        LogManager.resetCustomLogDirectoryForTesting()
        if let tempDir {
            try? FileManager.default.removeItem(at: tempDir)
        }
        try super.tearDownWithError()
    }

    func testTwoSpaceIndentationVerbosityGateForKb() throws {
        LogManager.initialize(currentVersion: "6.0.0", logDirectory: tempDir)
        LogManager.setAdvancedLogging(false)

        // Default `in: nil` uses the directory configured in `initialize`.
        LogManager.kb("directMode=true")
        LogManager.kb("  [AX] read 42 utf16, caret16=42")

        let kbURL = tempDir.appendingPathComponent("keyboard_debug.log")

        let kbWhenOff = try String(contentsOf: kbURL, encoding: .utf8)
        XCTAssertTrue(kbWhenOff.contains("directMode=true"))
        XCTAssertFalse(kbWhenOff.contains("[AX] read 42 utf16"))

        // Enable advanced logging -> 2-space trace is now written
        LogManager.setAdvancedLogging(true)
        LogManager.kb("  [AX] read 99 utf16, caret16=50")

        let kbWhenOn = try String(contentsOf: kbURL, encoding: .utf8)
        XCTAssertTrue(kbWhenOn.contains("[AX] read 99 utf16, caret16=50"))
    }

    func testPreExistingLogWithoutVersionMarkerRotatesToUnknown() throws {
        // Simulate upgrading from a build that predates LogManager (no last_version.txt).
        let liveURL = tempDir.appendingPathComponent("keyboard_debug.log")
        try "[KB] 12:00:00.000 legacy log line\n".write(to: liveURL, atomically: true, encoding: .utf8)

        LogManager.initialize(currentVersion: "6.0.0", logDirectory: tempDir)

        XCTAssertFalse(FileManager.default.fileExists(atPath: liveURL.path))
        let unknownArchive = tempDir.appendingPathComponent("keyboard_debug.vunknown.log")
        XCTAssertTrue(FileManager.default.fileExists(atPath: unknownArchive.path))
        let archiveContent = try String(contentsOf: unknownArchive, encoding: .utf8)
        XCTAssertTrue(archiveContent.contains("legacy log line"))
    }

    func testVersionChangeRotatesLiveLogsAndPrunesArchives() throws {
        // First launch on v6.0.0
        LogManager.initialize(currentVersion: "6.0.0", logDirectory: tempDir)
        LogManager.kb("session 6.0.0")

        let liveURL = tempDir.appendingPathComponent("keyboard_debug.log")
        XCTAssertTrue(FileManager.default.fileExists(atPath: liveURL.path))

        // Same version re-launch does not rotate
        LogManager.initialize(currentVersion: "6.0.0", logDirectory: tempDir)
        XCTAssertTrue(FileManager.default.fileExists(atPath: liveURL.path))
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: tempDir.appendingPathComponent("keyboard_debug.v6.0.0.log").path
        ))

        // Upgrade to v6.0.1 -> rotates keyboard_debug.log to keyboard_debug.v6.0.0.log
        LogManager.initialize(currentVersion: "6.0.1", logDirectory: tempDir)
        XCTAssertFalse(FileManager.default.fileExists(atPath: liveURL.path))
        let archive600 = tempDir.appendingPathComponent("keyboard_debug.v6.0.0.log")
        XCTAssertTrue(FileManager.default.fileExists(atPath: archive600.path))
        try FileManager.default.setAttributes(
            [.modificationDate: Date(timeIntervalSinceNow: -30)],
            ofItemAtPath: archive600.path
        )

        // Write in 6.0.1 and upgrade to 6.0.2
        LogManager.kb("session 6.0.1")
        LogManager.initialize(currentVersion: "6.0.2", logDirectory: tempDir)
        let archive601 = tempDir.appendingPathComponent("keyboard_debug.v6.0.1.log")
        XCTAssertTrue(FileManager.default.fileExists(atPath: archive601.path))
        try FileManager.default.setAttributes(
            [.modificationDate: Date(timeIntervalSinceNow: -15)],
            ofItemAtPath: archive601.path
        )

        // Write in 6.0.2 and upgrade to 6.0.3 -> maxArchives = 2 prunes 6.0.0
        LogManager.kb("session 6.0.2")
        LogManager.initialize(currentVersion: "6.0.3", logDirectory: tempDir)
        let archive602 = tempDir.appendingPathComponent("keyboard_debug.v6.0.2.log")
        XCTAssertTrue(FileManager.default.fileExists(atPath: archive602.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: archive601.path))
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: archive600.path),
            "Oldest archive beyond maxArchives=2 should be pruned"
        )
    }

    func testOversizedLiveAndArchiveLogsTruncatedToLast1000LinesWithMalformedUTF8() throws {
        let liveURL = tempDir.appendingPathComponent("keyboard_debug.log")
        let oldArchiveURL = tempDir.appendingPathComponent("keyboard_debug.v5.9.9.log")
        let markerURL = tempDir.appendingPathComponent("last_version.txt")
        try "6.0.0".write(to: markerURL, atomically: true, encoding: .utf8)

        // Build a >10 MB log with 1,500 numbered lines (~7.5 KB each -> ~11.2 MB)
        // plus an invalid UTF-8 byte sequence on line 1 to verify lossy UTF-8 recovery.
        let padding = String(repeating: "x", count: 7_500)
        var lines: [String] = []
        lines.reserveCapacity(1_500)
        for i in 1...1_500 {
            lines.append("line-\(i) \(padding)")
        }
        var oversizedData = Data([0xFF, 0xFE, 0x0A]) // malformed UTF-8 first line
        oversizedData.append(Data((lines.joined(separator: "\n") + "\n").utf8))
        try oversizedData.write(to: liveURL, options: .atomic)
        try oversizedData.write(to: oldArchiveURL, options: .atomic)

        // Initialize with new version 6.0.1 -> should truncate both live and archive first, then rotate live
        LogManager.initialize(currentVersion: "6.0.1", logDirectory: tempDir)

        let rotatedURL = tempDir.appendingPathComponent("keyboard_debug.v6.0.0.log")
        XCTAssertTrue(FileManager.default.fileExists(atPath: rotatedURL.path))
        let rotatedContent = try String(contentsOf: rotatedURL, encoding: .utf8)
        let rotatedLines = rotatedContent.split(separator: "\n", omittingEmptySubsequences: true)

        // 1 truncation header + 1,000 kept lines = 1,001 lines
        XCTAssertEqual(rotatedLines.count, 1_001)
        XCTAssertTrue(rotatedLines.first?.contains("log truncated at startup") == true)
        XCTAssertTrue(rotatedLines[1].hasPrefix("line-501 "))
        XCTAssertTrue(rotatedLines.last?.hasPrefix("line-1500 ") == true)

        // Existing archive should also be truncated in place
        let archiveContent = try String(contentsOf: oldArchiveURL, encoding: .utf8)
        let archiveLines = archiveContent.split(separator: "\n", omittingEmptySubsequences: true)
        XCTAssertEqual(archiveLines.count, 1_001)
        XCTAssertTrue(archiveLines.first?.contains("log truncated at startup") == true)
    }

    func testClearLogsAndTotalSizeReporting() throws {
        LogManager.initialize(currentVersion: "6.0.0", logDirectory: tempDir)
        XCTAssertEqual(LogManager.totalLogSizeBytes(), 0)
        XCTAssertEqual(LogManager.totalLogSizeDescription(), "0 KB")

        LogManager.kb("lifecycle event 1")
        XCTAssertGreaterThan(LogManager.totalLogSizeBytes(), 0)
        XCTAssertEqual(LogManager.totalLogSizeDescription(), "1 KB")

        // Rotate and write more so both live and archive files exist
        LogManager.initialize(currentVersion: "6.0.1", logDirectory: tempDir)
        LogManager.kb("lifecycle event 2")
        XCTAssertGreaterThan(LogManager.totalLogSizeBytes(), 0)

        // Clear all logs via default directory
        LogManager.clearLogs()
        XCTAssertEqual(LogManager.totalLogSizeBytes(), 0)
        XCTAssertEqual(LogManager.totalLogSizeDescription(), "0 KB")
    }
}
