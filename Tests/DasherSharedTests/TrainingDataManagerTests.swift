import XCTest
@testable import DasherShared

final class TrainingDataManagerTests: XCTestCase {
    private var tempDir: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("DasherTrainingTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let tempDir {
            try? FileManager.default.removeItem(at: tempDir)
        }
        try super.tearDownWithError()
    }

    func testResolveUserDirectoryNeverFallsBackToReadOnlyDataDir() throws {
        let fakeBundleDataDir = tempDir.appendingPathComponent("BundleData", isDirectory: true).path
        let fakeAppSupport = tempDir.appendingPathComponent("AppSupport", isDirectory: true)

        // When explicitUserDir is nil, falls back to Application Support/Dasher, not fakeBundleDataDir
        let resolvedNil = TrainingDataManager.resolveUserDirectory(
            explicitUserDir: nil,
            fallbackDataDir: fakeBundleDataDir,
            applicationSupportOverride: fakeAppSupport
        )
        XCTAssertNotEqual(resolvedNil, fakeBundleDataDir)
        XCTAssertEqual(resolvedNil, fakeAppSupport.appendingPathComponent("Dasher").path)
        XCTAssertTrue(FileManager.default.fileExists(atPath: resolvedNil))

        // When explicitUserDir equals fallbackDataDir, also falls back to Application Support/Dasher
        let resolvedSame = TrainingDataManager.resolveUserDirectory(
            explicitUserDir: fakeBundleDataDir,
            fallbackDataDir: fakeBundleDataDir,
            applicationSupportOverride: fakeAppSupport
        )
        XCTAssertEqual(resolvedSame, fakeAppSupport.appendingPathComponent("Dasher").path)
    }

    func testMigrateStrandedTrainingFilesMovesAndMergesWithNewlineBoundary() throws {
        let legacyDir = tempDir.appendingPathComponent("training", isDirectory: true)
        try FileManager.default.createDirectory(at: legacyDir, withIntermediateDirectories: true)

        // Case 1: Stranded file with no root counterpart -> moved to root
        let strandedFrench = legacyDir.appendingPathComponent("training_french_FR.txt")
        try "bonjour le monde\n".write(to: strandedFrench, atomically: true, encoding: .utf8)

        // Case 2: Stranded file where root counterpart already exists (without trailing newline) -> merged with '\n'
        let rootEnglish = tempDir.appendingPathComponent("training_english_GB.txt")
        try "adaptive root line without newline".write(to: rootEnglish, atomically: true, encoding: .utf8)
        let strandedEnglish = legacyDir.appendingPathComponent("training_english_GB.txt")
        try "imported legacy corpus".write(to: strandedEnglish, atomically: true, encoding: .utf8)

        TrainingDataManager.migrateStrandedTrainingFiles(in: tempDir.path)

        // Stranded directory should be cleaned up and removed
        XCTAssertFalse(FileManager.default.fileExists(atPath: legacyDir.path))

        // French moved to root
        let rootFrench = tempDir.appendingPathComponent("training_french_FR.txt")
        XCTAssertTrue(FileManager.default.fileExists(atPath: rootFrench.path))
        XCTAssertEqual(try String(contentsOf: rootFrench, encoding: .utf8), "bonjour le monde\n")

        // English merged with newline boundary at root
        XCTAssertEqual(
            try String(contentsOf: rootEnglish, encoding: .utf8),
            "adaptive root line without newline\nimported legacy corpus"
        )
    }

    func testMigrateStrandedFilesSkipsBundledDataDirectory() throws {
        let bundleTrainingDir = tempDir.appendingPathComponent("training", isDirectory: true)
        try FileManager.default.createDirectory(at: bundleTrainingDir, withIntermediateDirectories: true)
        try "game phrase".write(
            to: bundleTrainingDir.appendingPathComponent("gamemode_english_GB.txt"),
            atomically: true,
            encoding: .utf8
        )
        let bundledCorpus = bundleTrainingDir.appendingPathComponent("training_english_GB.txt")
        try "bundled corpus".write(to: bundledCorpus, atomically: true, encoding: .utf8)

        TrainingDataManager.migrateStrandedTrainingFiles(in: tempDir.path)

        // Bundled file must remain in place
        XCTAssertTrue(FileManager.default.fileExists(atPath: bundledCorpus.path))
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: tempDir.appendingPathComponent("training_english_GB.txt").path
        ))
    }

    func testPersistImportedTrainingTextEnforcesNewlineBoundaryAndLimits() throws {
        let enginePath = tempDir.appendingPathComponent("training_english_GB.txt").path

        // Engine wrote raw adaptive text without trailing newline
        try "hello world".write(toFile: enginePath, atomically: true, encoding: .utf8)

        // Import appends with a newline separator
        let targetURL = try TrainingDataManager.persistImportedTrainingText(
            "second line",
            engineReportedPath: enginePath,
            userDir: tempDir.path
        )
        XCTAssertEqual(targetURL.path, enginePath)
        XCTAssertEqual(
            TrainingDataManager.exportTrainingText(engineReportedPath: enginePath, userDir: tempDir.path),
            "hello world\nsecond line"
        )

        // Importing again when existing doesn't end with newline adds another separator
        try TrainingDataManager.persistImportedTrainingText(
            "third line\n",
            engineReportedPath: enginePath,
            userDir: tempDir.path
        )
        // Importing when existing ALREADY ends with '\n' does not double the newline
        try TrainingDataManager.persistImportedTrainingText(
            "fourth line",
            engineReportedPath: enginePath,
            userDir: tempDir.path
        )
        XCTAssertEqual(
            TrainingDataManager.exportTrainingText(engineReportedPath: enginePath, userDir: tempDir.path),
            "hello world\nsecond line\nthird line\nfourth line"
        )

        // Self-import guard
        XCTAssertThrowsError(
            try TrainingDataManager.persistImportedTrainingText(
                "self import",
                sourceFileURL: targetURL,
                engineReportedPath: enginePath,
                userDir: tempDir.path
            )
        ) { error in
            XCTAssertEqual(error as? TrainingDataManager.ImportError, .sameFileAsActiveTraining)
        }

        // Empty text guard
        XCTAssertThrowsError(
            try TrainingDataManager.persistImportedTrainingText(
                "",
                engineReportedPath: enginePath,
                userDir: tempDir.path
            )
        ) { error in
            XCTAssertEqual(error as? TrainingDataManager.ImportError, .emptyText)
        }
    }

    func testNoCrossAlphabetContaminationWhenActiveAlphabetFileIsMissing() throws {
        let englishFile = tempDir.appendingPathComponent("training_english_GB.txt")
        try "english training corpus".write(to: englishFile, atomically: true, encoding: .utf8)

        let frenchEnginePath = tempDir.appendingPathComponent("training_french_FR.txt").path
        // Active alphabet is French, which has no user training file yet:
        // fileSize and exportTrainingText must NOT fall back to English!
        XCTAssertEqual(
            TrainingDataManager.fileSize(engineReportedPath: frenchEnginePath, userDir: tempDir.path),
            0
        )
        XCTAssertNil(
            TrainingDataManager.exportTrainingText(engineReportedPath: frenchEnginePath, userDir: tempDir.path)
        )
        // But hasAnyUserTrainingFiles is true because English training exists
        XCTAssertTrue(TrainingDataManager.hasAnyUserTrainingFiles(in: tempDir.path))
    }

    func testMigrateV5TrainingFileMergesIntoExistingV6RootFile() throws {
        let v5File = tempDir.appendingPathComponent("v5_training_english_GB.txt")
        let v6File = tempDir.appendingPathComponent("training_english_GB.txt")

        try "v5 historical corpus".write(to: v5File, atomically: true, encoding: .utf8)
        try "v6 adaptive word".write(to: v6File, atomically: true, encoding: .utf8)

        // First migration merges v5 into v6 with newline separator
        let didMigrate = try TrainingDataManager.migrateV5TrainingFile(from: v5File, to: v6File)
        XCTAssertTrue(didMigrate)
        XCTAssertEqual(
            try String(contentsOf: v6File, encoding: .utf8),
            "v6 adaptive word\nv5 historical corpus"
        )

        // Second migration is idempotent (already contains v5 data)
        let didMigrateAgain = try TrainingDataManager.migrateV5TrainingFile(from: v5File, to: v6File)
        XCTAssertFalse(didMigrateAgain)

        // Same-path guard (when v5 dir == v6 dir) succeeds without duplicating content
        let samePathResult = try TrainingDataManager.migrateV5TrainingFile(from: v6File, to: v6File)
        XCTAssertTrue(samePathResult)
        XCTAssertEqual(
            try String(contentsOf: v6File, encoding: .utf8),
            "v6 adaptive word\nv5 historical corpus"
        )
    }

    func testResetTrainingDataDeletesRootAndLegacyTrainingFilesOnly() throws {
        let rootTraining = tempDir.appendingPathComponent("training_english_GB.txt")
        let rootGerman = tempDir.appendingPathComponent("training_german_DE.txt")
        let settingsFile = tempDir.appendingPathComponent("dasher_settings.xml")
        let legacyDir = tempDir.appendingPathComponent("training", isDirectory: true)
        try FileManager.default.createDirectory(at: legacyDir, withIntermediateDirectories: true)
        let legacyTraining = legacyDir.appendingPathComponent("training_spanish_ES.txt")

        try "en".write(to: rootTraining, atomically: true, encoding: .utf8)
        try "de".write(to: rootGerman, atomically: true, encoding: .utf8)
        try "<settings/>".write(to: settingsFile, atomically: true, encoding: .utf8)
        try "es".write(to: legacyTraining, atomically: true, encoding: .utf8)

        XCTAssertGreaterThan(
            TrainingDataManager.fileSize(engineReportedPath: rootTraining.path, userDir: tempDir.path),
            0
        )

        TrainingDataManager.resetTrainingData(in: tempDir.path)

        XCTAssertFalse(FileManager.default.fileExists(atPath: rootTraining.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: rootGerman.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: legacyTraining.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: settingsFile.path))
        XCTAssertEqual(
            TrainingDataManager.fileSize(engineReportedPath: rootTraining.path, userDir: tempDir.path),
            0
        )
        XCTAssertEqual(TrainingDataManager.sizeDescription(bytes: 0), "No custom training data")
    }
}
