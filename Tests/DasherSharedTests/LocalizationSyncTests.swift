import XCTest

final class LocalizationSyncTests: XCTestCase {

    private var repoRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // DasherSharedTests
            .deletingLastPathComponent() // Tests
            .deletingLastPathComponent() // repo root
    }

    func testGenFromSharedCheckPassesWithZeroDrift() throws {
        let script = repoRoot.appendingPathComponent("Localization/gen-from-shared.py")
        XCTAssertTrue(FileManager.default.fileExists(atPath: script.path))

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        proc.arguments = ["python3", script.path, "--check"]
        proc.currentDirectoryURL = repoRoot

        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = pipe

        try proc.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        proc.waitUntilExit()

        let output = String(data: data, encoding: .utf8) ?? ""
        XCTAssertEqual(
            proc.terminationStatus,
            0,
            "Localization/gen-from-shared.py --check failed:\n\(output)"
        )
    }

    func testCriticalSharedKeysPresentAndTranslatedInXCStrings() throws {
        let xcURL = repoRoot.appendingPathComponent("Localization/Localizable.xcstrings")
        let data = try Data(contentsOf: xcURL)
        let json = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let strings = try XCTUnwrap(json["strings"] as? [String: [String: Any]])

        // Issue #56: verify previously missing SpeechSettingsView, DasherSettingsView,
        // drifted AnalyticsViews disclaimers, DiagnosticLoggingSection, and Direct Mode
        // mini-bar strings are all in Localizable.xcstrings with 32-locale translations.
        let requiredTranslatedKeys = [
            "TTS Engine",
            "No credentials required",
            "Load Voices",
            "Rate",
            "Pitch",
            "Volume",
            "Stop",
            "Preview",
            "Default",
            "Output Font",
            "Advanced logging",
            "Clear logs",
            "Control nodes: move, delete, clear, speak, pause",
            "Delete (hold to repeat)",
            "Move caret left (hold to repeat)",
            "Move caret right (hold to repeat)",
            "Re-anchor predictions to the caret (read the sentence around your cursor)",
            "New session (clear text and context)",
            "Dasher collects anonymous, privacy-respecting analytics to understand usage patterns and fix crashes. No typed text, clipboard contents, or personal information is ever collected.\n\nYou can change this anytime in Settings > Privacy.",
            "Dasher collects anonymous analytics to understand usage and fix crashes. No typed text, clipboard, or personal info is ever collected. See the open event schema at github.com/dasher-project/Dasher-Apple.",
            "This deletes your accumulated training data. The language model will return to built-in defaults on next launch. This cannot be undone.",
            "%@ cps · %lld wpm"
        ]

        for key in requiredTranslatedKeys {
            guard let entry = strings[key],
                  let locs = entry["localizations"] as? [String: Any] else {
                XCTFail("Missing key in Localizable.xcstrings: \(key)")
                continue
            }
            XCTAssertGreaterThanOrEqual(
                locs.count,
                30,
                "Expected >= 30 locale translations for shared key '\(key)', found \(locs.count)"
            )
        }

        // Also verify Apple-only static and format keys are registered in the catalog scaffold
        let requiredPresentKeys = [
            "Voice",
            "Appearance",
            "Dwell Duration",
            "Sending to %@",
            "%lld voices",
            "%lld ms per step",
            "Phrase %lld · %@ wpm"
        ]
        for key in requiredPresentKeys {
            XCTAssertNotNil(strings[key], "Expected key '\(key)' to be registered in Localizable.xcstrings")
        }
    }
}
