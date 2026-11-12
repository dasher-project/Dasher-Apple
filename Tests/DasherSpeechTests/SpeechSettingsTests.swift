import Foundation
import XCTest
@testable import DasherSpeech

final class SpeechSettingsTests: XCTestCase {
    @MainActor
    func testMigratesAndKeepsProviderCredentialsAndVoicesSeparate() async throws {
        let suite = "DasherSpeechTests.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set("azure", forKey: "tts_engine")
        defaults.set(try JSONEncoder().encode(["subscriptionKey": "test-azure", "apiKey": "test-old-key"]), forKey: "tts_credentials")
        defaults.set("azure-voice", forKey: "tts_voice")

        let service = SpeechService(defaults: defaults)
        XCTAssertEqual(service.selectedEngineID, "azure")
        XCTAssertEqual(service.credential("subscriptionKey"), "test-azure")
        XCTAssertEqual(service.credential("apiKey"), "")
        XCTAssertEqual(service.selectedVoice, "azure-voice")

        service.selectedEngineID = "openai"
        XCTAssertEqual(service.credential("subscriptionKey"), "")
        XCTAssertNil(service.selectedVoice)
        service.setCredential("apiKey", value: "test-openai")
        service.selectedVoice = "alloy"

        service.selectedEngineID = "azure"
        XCTAssertEqual(service.credential("subscriptionKey"), "test-azure")
        XCTAssertEqual(service.selectedVoice, "azure-voice")

        let reopened = SpeechService(defaults: defaults)
        reopened.selectedEngineID = "openai"
        XCTAssertEqual(reopened.credential("apiKey"), "test-openai")
        XCTAssertEqual(reopened.selectedVoice, "alloy")
    }
}

#if os(macOS) || os(iOS)
import AVFoundation

extension SpeechSettingsTests {
    func testCatalogFindsModelsAndReportsUnsupportedDownloads() throws {
        let models = try SherpaModel.bundledCatalog()
        XCTAssertGreaterThan(models.count, 1700)
        XCTAssertEqual(models.first?.id, SpeechModelStorage.englishModelID)
        let english = try XCTUnwrap(models.first(where: { $0.id == "inflect-en-nano-v2" }))
        let french = try XCTUnwrap(models.first(where: { $0.id == "mms_fra" }))
        let germanPiper = try XCTUnwrap(models.first(where: { $0.id == "piper-de_DE-thorsten-medium" }))
        XCTAssertTrue(english.matches("inflect english"))
        XCTAssertTrue(french.matches("French MMS"))
        XCTAssertFalse(french.matches("French Kokoro"))
        XCTAssertNil(SpeechModelStorage.downloadUnavailableReason(for: english))
        XCTAssertNil(SpeechModelStorage.downloadUnavailableReason(for: french))
        XCTAssertNotNil(SpeechModelStorage.downloadUnavailableReason(for: germanPiper))
        XCTAssertFalse(SpeechModelStorage.isModelID("../invalid"))
    }

    @MainActor
    func testDownloadedEnglishModelProducesPlayableAudio() async throws {
        guard ProcessInfo.processInfo.environment["DASHER_TEST_DOWNLOAD_ENGLISH_VOICE"] == "1" else {
            throw XCTSkip("Set DASHER_TEST_DOWNLOAD_ENGLISH_VOICE=1 to fetch and test the English model.")
        }
        let models = URL.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: models) }
        try await SpeechModelStorage.downloadEnglishModel(to: models)
        XCTAssertTrue(SpeechModelStorage.isInstalled(SpeechModelStorage.englishModelID, in: models))

        let backend = RustSpeechBackend()
        let audio = try await backend.synthesize(
            "Hello from Dasher.", engineID: SpeechEngine.sherpaID,
            credentials: ["modelId": SpeechModelStorage.englishModelID, "modelPath": models.path],
            voice: nil, rate: 1, pitch: 1, volume: 1
        )
        let player = try AVAudioPlayer(data: audio)
        XCTAssertEqual(player.numberOfChannels, 1)
        XCTAssertGreaterThan(player.duration, 0.25)
    }

    @MainActor
    func testDownloadedFrenchMMSProducesPlayableAudio() async throws {
        guard ProcessInfo.processInfo.environment["DASHER_TEST_DOWNLOAD_MMS_VOICE"] == "1" else {
            throw XCTSkip("Set DASHER_TEST_DOWNLOAD_MMS_VOICE=1 to fetch and test the French MMS model.")
        }
        let models = URL.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: models) }
        let french = try XCTUnwrap(SherpaModel.bundledCatalog().first(where: { $0.id == "mms_fra" }))
        try await SpeechModelStorage.download(french, to: models)
        XCTAssertTrue(SpeechModelStorage.isInstalled(french.id, in: models))

        let audio = try await RustSpeechBackend().synthesize(
            "Bonjour, ceci est un essai de Dasher.", engineID: SpeechEngine.sherpaID,
            credentials: ["modelId": french.id, "modelPath": models.path],
            voice: nil, rate: 1, pitch: 1, volume: 1
        )
        XCTAssertGreaterThan(try AVAudioPlayer(data: audio).duration, 0.25)
    }
}
#endif
