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
    @MainActor
    func testDownloadedEnglishModelProducesPlayableAudio() async throws {
        guard ProcessInfo.processInfo.environment["DASHER_TEST_DOWNLOAD_ENGLISH_VOICE"] == "1" else {
            throw XCTSkip("Set DASHER_TEST_DOWNLOAD_ENGLISH_VOICE=1 to fetch and test the English model.")
        }
        let models = URL.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: models) }
        try await SpeechModelStorage.downloadEnglishModel(to: models)

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
}
#endif
