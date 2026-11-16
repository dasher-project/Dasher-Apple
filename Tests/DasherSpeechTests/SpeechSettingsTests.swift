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
        let alan = try XCTUnwrap(models.first(where: { $0.id == "piper-en_GB-alan-medium" }))
        let polishPiper = try XCTUnwrap(models.first(where: { $0.id == "piper-pl_PL-gosia-medium" }))
        XCTAssertTrue(english.matches("inflect english"))
        XCTAssertTrue(french.matches("French MMS"))
        XCTAssertFalse(french.matches("French Kokoro"))
        XCTAssertEqual(alan.displayName, "Alan")
        XCTAssertEqual(alan.voiceMetadata.type, "Piper")
        XCTAssertEqual(alan.voiceMetadata.gender, .male)
        XCTAssertEqual(alan.voiceMetadata.languages.first?.code, "en-GB")
        XCTAssertTrue(alan.matches("alan piper male"))
        XCTAssertEqual(french.voiceMetadata.gender, .unspecified)
        XCTAssertEqual(french.voiceMetadata.languages.first?.filterName, VoiceLanguage("fr-FR").filterName)
        XCTAssertNil(SpeechModelStorage.downloadUnavailableReason(for: english))
        XCTAssertNil(SpeechModelStorage.downloadUnavailableReason(for: french))
        for id in [
            "piper-de_DE-thorsten-medium", "piper-en_US-amy-low", "piper-fr_FR-siwis-medium",
            "piper-es_ES-sharvard-medium", "piper-pt_BR-faber-medium", "piper-it_IT-paola-medium",
            "piper-ru_RU-dmitri-medium",
        ] {
            let model = try XCTUnwrap(models.first(where: { $0.id == id }), id)
            XCTAssertTrue(model.usesG2PBundle, id)
            XCTAssertNil(SpeechModelStorage.downloadUnavailableReason(for: model), id)
        }
        XCTAssertEqual(polishPiper.readiness, "blocked:bundle-not-validated")
        XCTAssertNotNil(SpeechModelStorage.downloadUnavailableReason(for: polishPiper))
        XCTAssertFalse(SpeechModelStorage.isModelID("../invalid"))
    }

    func testVoiceFiltersCombineLanguageGenderTypeAndSearch() {
        let language = VoiceLanguage(wrapperLabel: "English (United Kingdom) [en-GB]")
        let type = SpeechVoice.providerVoiceType(engineID: "azure", id: "en-GB-SoniaNeural")
        let metadata = VoiceMetadata(languages: [language], gender: VoiceGender("Female"), type: type)
        var filters = VoiceFilters(language: VoiceLanguage("en-US").filterName, gender: .female, type: type)
        XCTAssertEqual(language.code, "en-GB")
        XCTAssertEqual(language.name, "English (United Kingdom)")
        XCTAssertEqual(type, String(localized: "Neural"))
        XCTAssertTrue(filters.matches(metadata, search: "sonia en-gb", terms: ["Sonia"]))
        XCTAssertFalse(filters.matches(metadata, search: "sonia fr-fr", terms: ["Sonia"]))
        XCTAssertFalse(filters.matches(metadata, search: "sonia \(VoiceGender.male.title)", terms: ["Sonia"]))
        filters.type = "Standard"
        XCTAssertFalse(filters.matches(metadata, search: "", terms: []))
        filters.type = type
        filters.gender = .male
        XCTAssertFalse(filters.matches(metadata, search: "", terms: []))
        filters.gender = .female
        filters.language = VoiceLanguage("fr-FR").filterName
        XCTAssertFalse(filters.matches(metadata, search: "", terms: []))
    }

    func testCredentialPromptsUseUserFacingText() throws {
        let azure = try XCTUnwrap(SpeechEngine.available().first { $0.id == "azure" })
        let subscriptionKey = try XCTUnwrap(azure.fields.first { $0.id == "subscriptionKey" })
        let region = try XCTUnwrap(azure.fields.first { $0.id == "region" })
        XCTAssertEqual(subscriptionKey.label, "Subscription key")
        XCTAssertEqual(region.label, "Region")
        XCTAssertTrue(region.choices.contains("eastus"))

        let field = SpeechEngine.Field(
            id: "apiKey", label: "API Key", kind: .secret,
            defaultValue: "test-secret", placeholder: "Enter CredentialKey(key: \"apiKey\")"
        )
        XCTAssertNil(field.prompt)
        let url = SpeechEngine.Field(
            id: "endpoint", label: "Endpoint", kind: .text, defaultValue: "https://example.org/",
            placeholder: "Enter your service URL"
        )
        XCTAssertEqual(url.prompt, "Enter your service URL")
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
    func testDownloadedPiperProducesPlayableAudio() async throws {
        let environment = ProcessInfo.processInfo.environment
        guard let modelID = environment["DASHER_TEST_PIPER_MODEL_ID"] else {
            throw XCTSkip("Set DASHER_TEST_PIPER_MODEL_ID to download and test a Piper voice.")
        }
        let modelsDirectory = environment["DASHER_TEST_PIPER_MODELS_DIR"]
        let models = if let directory = modelsDirectory {
            URL(filePath: directory, directoryHint: .isDirectory)
        } else {
            URL.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        }
        defer {
            if modelsDirectory == nil {
                try? FileManager.default.removeItem(at: models)
            }
        }
        let model = try XCTUnwrap(SherpaModel.bundledCatalog().first(where: { $0.id == modelID }))
        if environment["DASHER_TEST_PIPER_USE_INSTALLED"] != "1" {
            try await SpeechModelStorage.download(model, to: models)
        }
        XCTAssertTrue(SpeechModelStorage.isInstalled(model.id, in: models))

        let audio = try await RustSpeechBackend().synthesize(
            environment["DASHER_TEST_PIPER_TEXT"] ?? "Blorpinxel!", engineID: SpeechEngine.sherpaID,
            credentials: ["modelId": model.id, "modelPath": models.path],
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
