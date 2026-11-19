import Foundation
import XCTest
@testable import DasherShared

final class BundledLanguageDataTests: XCTestCase {
    func testLocaleAlphabetListPreservesBilingualSelectionAndShowAll() {
        let metadata = [("English", "en"), ("Español", "es"), ("Français", "fr")].map { name, language in
            AlphabetInfo(id: name, orientation: "ltr", lang: language, script: "Latn",
                         scriptName: "Latin", chars: 30, source: "maintained")
        }
        let names = metadata.map(\.id) + ["My alphabet"]
        XCTAssertEqual(
            AlphabetIndex.visibleNames(names, selectedID: "English", showAll: false, localeTag: "en_GB", index: metadata),
            ["English", "My alphabet"]
        )
        XCTAssertEqual(
            AlphabetIndex.visibleNames(names, selectedID: "Español", showAll: false, localeTag: "en-GB", index: metadata),
            ["English", "Español", "My alphabet"]
        )
        XCTAssertEqual(
            AlphabetIndex.visibleNames(names, selectedID: "Español", showAll: true, localeTag: "en-GB", index: metadata),
            names
        )
        XCTAssertEqual(
            AlphabetIndex.visibleNames(names, selectedID: "Español", showAll: false, localeTag: "es-MX", index: metadata),
            ["Español", "My alphabet"]
        )
    }

    func testFullAppBundleIncludesSpanishAlphabetAndTraining() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let destination = FileManager.default.temporaryDirectory
            .appendingPathComponent("DasherLanguageData-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: destination) }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["python3", root.appendingPathComponent("Scripts/prepare-engine-data.py").path, destination.path]
        let output = Pipe()
        process.standardOutput = output
        process.standardError = output
        try process.run()
        let result = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0, String(decoding: result, as: UTF8.self))

        let alphabet = "autoConverted/alphabet.espaol.spanish.with.punctuation.and.numerals.xml"
        let source = root.appendingPathComponent("DasherCore/Data/alphabets").appendingPathComponent(alphabet)
        let bundled = destination.appendingPathComponent("alphabets").appendingPathComponent(alphabet)
        XCTAssertEqual(try Data(contentsOf: bundled), try Data(contentsOf: source))
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: destination.appendingPathComponent("alphabets/alphabet.english.x-sampa.phonetic.xml").path
        ))
        let training = destination.appendingPathComponent("training", isDirectory: true)
        let spanish = try String(contentsOf: training.appendingPathComponent("training_wa_es_Latn.txt"), encoding: .utf8)
        XCTAssertGreaterThan(spanish.utf8.count, 10_000)
        XCTAssertEqual(
            try String(contentsOf: training.appendingPathComponent("training_spanish_ES.txt"), encoding: .utf8),
            spanish.precomposedStringWithCanonicalMapping
        )
        XCTAssertEqual(
            try String(contentsOf: training.appendingPathComponent("training_spanishC_ES.txt"), encoding: .utf8),
            spanish.decomposedStringWithCanonicalMapping
        )
        let index = AlphabetIndex.load(dataDir: destination.path)
        XCTAssertGreaterThan(index.count, 400)
        let suggested = try XCTUnwrap(AlphabetIndex.suggest(list: index, localeTag: "es-ES"))
        XCTAssertEqual(suggested.lang, "es")
        let selected = try XCTUnwrap(index.first { $0.id == "Español / Spanish with punctuation and numerals" })
        XCTAssertEqual(suggested.id, selected.id)

        struct TrainingIndex: Decodable {
            struct Entry: Decodable {
                let id: String
                let training: String?
                let training_available: Bool
            }
            let alphabets: [Entry]
        }
        let bundledIndex = try Data(contentsOf: destination.appendingPathComponent("alphabets/alphabet_index.json"))
        XCTAssertEqual(
            bundledIndex,
            try Data(contentsOf: root.appendingPathComponent("DasherCore/Data/alphabets/alphabet_index.json"))
        )
        let entries = try JSONDecoder().decode(
            TrainingIndex.self, from: bundledIndex
        ).alphabets
        let supplied = root.appendingPathComponent("DasherCore/Data/training")
        for entry in entries {
            guard entry.training_available, let filename = entry.training else { continue }
            XCTAssertEqual(
                try Data(contentsOf: training.appendingPathComponent(filename)),
                try Data(contentsOf: supplied.appendingPathComponent(filename)),
                entry.id
            )
        }
    }
}
