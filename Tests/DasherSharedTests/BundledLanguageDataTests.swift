import Foundation
import XCTest
@testable import DasherShared

final class BundledLanguageDataTests: XCTestCase {
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
    }
}
