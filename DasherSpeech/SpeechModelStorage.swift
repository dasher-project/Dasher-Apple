import Foundation
#if os(macOS) || os(iOS)
import CBZip2
import CryptoKit
import SWCompression
#endif

struct SpeechModelStorage {
    static var root: URL {
        URL.applicationSupportDirectory.appending(path: "Dasher/Speech", directoryHint: .isDirectory)
    }

    static var models: URL { root.appending(path: "Models", directoryHint: .isDirectory) }
    static let englishModelID = "inflect-en-nano-v2"

    #if os(macOS) || os(iOS)
    private static let githubAssets = URL(string: "https://github.com/k2-fsa/sherpa-onnx/releases/download/tts-models/")!
    private static let mmsRepository = "willwade/mms-tts-multilingual-models-onnx"
    private static let mmsRevision = "4f49fc254f11ddb0e35fbf25b6e48b04463a6779"
    private static let hub = URL(string: "https://huggingface.co")!
    private static let verificationFile = ".dasher-verified-model"

    static func isModelID(_ id: String) -> Bool {
        id.range(of: #"^[A-Za-z0-9][A-Za-z0-9_.-]*$"#, options: .regularExpression) != nil
    }

    static func downloadUnavailableReason(for model: SherpaModel) -> String? {
        guard model.engines?.split(separator: ",").contains(where: {
            $0.trimmingCharacters(in: .whitespaces) == "sherpa-onnx"
        }) != false else {
            return String(localized: "Requires a different speech engine.")
        }
        if model.modelType == "mms", mmsDirectory(for: model) != nil { return nil }
        guard isModelID(model.id), model.url.absoluteString.hasPrefix(githubAssets.absoluteString),
              model.url.lastPathComponent.hasSuffix(".tar.bz2"),
              archiveChecksum(for: model) != nil else {
            return String(localized: "This model has no verified download that Dasher can install.")
        }
        switch model.modelType {
        case "vits" where model.developer == "piper" && !model.isEnglishOnly:
            return SpeechSetupError.modelNeedsLexicon.errorDescription
        case "vits", "kokoro", "kitten", "supertonic", "pocket", "matcha", "zipvoice":
            return nil
        default:
            return String(localized: "Dasher does not install the extra files required by this model yet.")
        }
    }

    static func installedModelIDs(in directory: URL = models) -> Set<String> {
        Set(contents(of: directory).lazy.map(\.lastPathComponent).filter { isInstalled($0, in: directory) })
    }

    static func isInstalled(_ modelID: String, in directory: URL = models) -> Bool {
        guard isModelID(modelID) else { return false }
        let folder = directory.appending(path: modelID, directoryHint: .isDirectory)
        if modelID == englishModelID, ["model.onnx", "tokens.txt", "lexicon.txt"].allSatisfy({ contains($0, in: folder) }) {
            return true
        }
        return (try? String(contentsOf: folder.appending(path: verificationFile), encoding: .utf8)) == modelID
    }

    static func downloadEnglishModel(to directory: URL = models) async throws {
        guard let model = try SherpaModel.bundledCatalog().first(where: { $0.id == englishModelID }) else {
            throw SpeechSetupError.modelDownloadFailed
        }
        try await download(model, to: directory)
    }

    static func download(_ model: SherpaModel, to directory: URL = models) async throws {
        guard downloadUnavailableReason(for: model) == nil else { throw SpeechSetupError.modelDownloadFailed }
        let manager = FileManager.default
        let staging = directory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        let unpacked = staging.appending(path: "model", directoryHint: .isDirectory)
        try manager.createDirectory(at: unpacked, withIntermediateDirectories: true)
        defer { try? manager.removeItem(at: staging) }

        let modelFolder: URL
        if let language = mmsDirectory(for: model) {
            try await downloadMMS(language, into: unpacked)
            modelFolder = unpacked
        } else {
            guard let checksum = archiveChecksum(for: model) else { throw SpeechSetupError.modelDownloadFailed }
            let archive = staging.appending(path: "model.tar.bz2")
            try await fetch(model.url, checksum: .sha256(checksum), to: archive)
            let tar = staging.appending(path: "model.tar")
            try decompress(archive, to: tar)
            try extract(tar, to: unpacked)
            modelFolder = try findModelFolder(in: unpacked)
            if ["vits", "kokoro", "kitten", "matcha", "zipvoice"].contains(model.modelType), !hasLexicon(in: modelFolder) {
                guard model.isEnglishOnly else {
                    throw SpeechSetupError.modelNeedsLexicon
                }
                try await fetch(
                    githubAssets.appending(path: "lexicon-en-us.txt"),
                    checksum: .sha256("8b67ae549a465eee78f92ecb74644ad90c3c58ce65f19c68baf85878a10ef73a"),
                    to: modelFolder.appending(path: "lexicon.txt")
                )
            }
            if model.modelType == "kitten", !contains("model.onnx", in: modelFolder),
               let modelFile = ["model.int8.onnx", "model.fp16.onnx"].first(where: { contains($0, in: modelFolder) }) {
                try manager.moveItem(at: modelFolder.appending(path: modelFile), to: modelFolder.appending(path: "model.onnx"))
            }
            try await downloadVocoderIfNeeded(for: model, into: modelFolder)
        }

        try validate(model, in: modelFolder)
        try model.id.write(to: modelFolder.appending(path: verificationFile), atomically: true, encoding: .utf8)
        try Task.checkCancellation()
        var destination = directory.appending(path: model.id, directoryHint: .isDirectory)
        if manager.fileExists(atPath: destination.path) {
            _ = try manager.replaceItemAt(destination, withItemAt: modelFolder)
        } else {
            try manager.moveItem(at: modelFolder, to: destination)
        }
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? destination.setResourceValues(values)
    }

    private static func archiveChecksum(for model: SherpaModel) -> String? {
        // The upstream release replaced these files after registry 1.1.0.
        // Keep the replacement digests pinned until the registry includes them.
        // https://github.com/AACTools/sherpa-onnx-tts-models/issues/3
        let updated: [String: String] = [
            "kokoro-zh_en-int8": "259c9c8bc906d6078e4e0570421885dabb68b539c2f970fcbb890a58eeaf3e9c",
            "kokoro-zh_en-multi-lang": "b78e1ac42b852e839cceaafbe88f66806bf5860992d1d7b9a3f2ad1198427aed",
            "icefall-en-ljspeech": "cff849fee69d7d3b22e0b0267aa6b863e32d05039a1eca963765a314a73450c0",
            "icefall-en-ljspeech-low": "e5ae18c97b566099a2a748f243d4d44ea7cd188acc34e3533a2adc2565c9f845",
            "icefall-en-ljspeech-medium": "93efae74fe0c72199c51b11ca7acb20b4966c2dc8b728109910266784f39f720",
            "icefall-zh-baker": "ae70096b19c6e283ea351a26b8a718ce6427c8bde8c1da22eb46a5478d39a69b",
        ]
        guard let checksum = updated[model.id] ?? model.sha256,
              checksum.range(of: #"^[a-fA-F0-9]{64}$"#, options: .regularExpression) != nil else { return nil }
        return checksum
    }

    private static func downloadVocoderIfNeeded(for model: SherpaModel, into folder: URL) async throws {
        let name: String
        let digest: String
        switch model.modelType {
        case "matcha" where model.id == "icefall-zh_en-zh-en":
            name = "vocos-16khz-univ.onnx"
            digest = "b599142a1fb8ff03de3e84ac35ff537c619e56f4267a6fe894851a42844acf9e"
        case "matcha":
            name = "vocos-22khz-univ.onnx"
            digest = "0574a135aa1db2de6e181050db2ec528496cacd4a4701fc5d7faf9f9804c0081"
        case "zipvoice":
            name = "vocos_24khz.onnx"
            digest = "bcb3b970e384161c4d634f0bb9e999ff1c471b34c9bc0b1049a5014065ed3cc0"
        default:
            return
        }
        let release = URL(string: "https://github.com/k2-fsa/sherpa-onnx/releases/download/vocoder-models/")!
        let target = folder.appending(path: "vocoder.onnx")
        if FileManager.default.fileExists(atPath: target.path) {
            try FileManager.default.removeItem(at: target)
        }
        try await fetch(release.appending(path: name), checksum: .sha256(digest), to: target)
    }

    private enum Checksum {
        case sha256(String)
        case gitBlob(String, size: Int)

        func matches(_ file: URL) throws -> Bool {
            let stream = try FileHandle(forReadingFrom: file)
            defer { try? stream.close() }
            switch self {
            case .sha256(let expected):
                var hash = SHA256()
                while let data = try stream.read(upToCount: 1_048_576), !data.isEmpty {
                    try Task.checkCancellation()
                    hash.update(data: data)
                }
                return hash.finalize().map { String(format: "%02x", $0) }.joined() == expected.lowercased()
            case .gitBlob(let expected, let size):
                let data = try stream.read(upToCount: size + 1) ?? Data()
                guard data.count == size else { return false }
                var hash = Insecure.SHA1()
                hash.update(data: Data("blob \(size)\0".utf8))
                hash.update(data: data)
                return hash.finalize().map { String(format: "%02x", $0) }.joined() == expected
            }
        }
    }

    private static func fetch(_ url: URL, checksum: Checksum, to destination: URL) async throws {
        let (file, response) = try await URLSession.shared.download(from: url)
        defer { try? FileManager.default.removeItem(at: file) }
        guard (response as? HTTPURLResponse)?.statusCode == 200,
              try checksum.matches(file) else { throw SpeechSetupError.modelDownloadFailed }
        try FileManager.default.moveItem(at: file, to: destination)
    }

    private struct HubFile: Decodable {
        struct LFS: Decodable { let oid: String }
        let path: String
        let oid: String
        let size: Int
        let lfs: LFS?
    }

    private static func mmsDirectory(for model: SherpaModel) -> String? {
        let components = model.url.pathComponents
        guard model.modelType == "mms", model.url.host == hub.host,
              components.count == 6, components[1...4].joined(separator: "/") == "\(mmsRepository)/resolve/main",
              model.id == "mms_\(components[5])" else { return nil }
        return components[5]
    }

    private static func downloadMMS(_ language: String, into folder: URL) async throws {
        let treeURL = hub.appending(path: "api/models/\(mmsRepository)/tree/\(mmsRevision)/\(language)")
        let (data, response) = try await URLSession.shared.data(from: treeURL)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw SpeechSetupError.modelDownloadFailed }
        let files = try JSONDecoder().decode([HubFile].self, from: data)
        for name in ["model.onnx", "tokens.txt", "lexicon.txt"] {
            guard let file = files.first(where: { $0.path == "\(language)/\(name)" }) else {
                if name == "lexicon.txt" { continue }
                throw SpeechSetupError.modelDownloadFailed
            }
            let checksum: Checksum
            if let lfs = file.lfs {
                checksum = .sha256(lfs.oid)
            } else {
                guard file.size > 0, file.size <= 16 * 1_048_576 else { throw SpeechSetupError.modelDownloadFailed }
                checksum = .gitBlob(file.oid, size: file.size)
            }
            try await fetch(
                hub.appending(path: "\(mmsRepository)/resolve/\(mmsRevision)/\(file.path)"),
                checksum: checksum,
                to: folder.appending(path: name)
            )
        }
    }

    private static func decompress(_ archive: URL, to tar: URL) throws {
        guard let source = fopen(archive.path, "rb") else { throw SpeechSetupError.modelDownloadFailed }
        defer { fclose(source) }
        var result = BZ_OK
        guard let reader = BZ2_bzReadOpen(&result, source, 0, 0, nil, 0), result == BZ_OK else {
            throw SpeechSetupError.modelDownloadFailed
        }
        defer { BZ2_bzReadClose(&result, reader) }
        guard FileManager.default.createFile(atPath: tar.path, contents: nil) else { throw SpeechSetupError.modelDownloadFailed }
        let output = try FileHandle(forWritingTo: tar)
        defer { try? output.close() }
        var buffer = Data(count: 1_048_576)
        var expandedSize = 0
        repeat {
            try Task.checkCancellation()
            let count = buffer.withUnsafeMutableBytes {
                BZ2_bzRead(&result, reader, $0.baseAddress, Int32($0.count))
            }
            expandedSize += Int(count)
            guard (result == BZ_OK || result == BZ_STREAM_END), count >= 0, expandedSize <= 2 * 1_024 * 1_048_576 else {
                throw SpeechSetupError.modelDownloadFailed
            }
            try output.write(contentsOf: buffer.prefix(Int(count)))
        } while result != BZ_STREAM_END
    }

    private static func extract(_ tar: URL, to folder: URL) throws {
        let input = try FileHandle(forReadingFrom: tar)
        defer { try? input.close() }
        var reader = TarReader(fileHandle: input)
        while try reader.process({ entry in
            guard let entry else { return false }
            try Task.checkCancellation()
            guard entry.info.type == .regular, let data = entry.data else { return true }
            let name = entry.info.name
            let path = name.split(separator: "/", omittingEmptySubsequences: false).drop(while: { $0 == "." })
            guard !path.isEmpty, path.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." }) else {
                throw SpeechSetupError.modelDownloadFailed
            }
            // Sherpa 2 does not use the legacy espeak data bundled in some archives.
            guard !path.contains("espeak-ng-data") else { return true }
            let target = folder.appending(path: path.joined(separator: "/"))
            guard !FileManager.default.fileExists(atPath: target.path) else { throw SpeechSetupError.modelDownloadFailed }
            try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: target)
            return true
        }) {}
    }

    private static func contents(of folder: URL) -> [URL] {
        (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.isDirectoryKey], options: .skipsHiddenFiles)) ?? []
    }

    private static func contains(_ file: String, in directory: URL) -> Bool {
        let values = try? directory.appending(path: file).resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
        return values?.isRegularFile == true && (values?.fileSize ?? 0) > 0
    }

    private static func hasLexicon(in folder: URL) -> Bool {
        contents(of: folder).contains {
            $0.lastPathComponent.hasPrefix("lexicon") && $0.pathExtension == "txt" && contains($0.lastPathComponent, in: folder)
        }
    }

    private static func findModelFolder(in folder: URL) throws -> URL {
        let entries = contents(of: folder)
        if entries.contains(where: { $0.pathExtension == "onnx" }) { return folder }
        let candidates = entries.filter { entry in
            (try? entry.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
                && contents(of: entry).contains(where: { $0.pathExtension == "onnx" })
        }
        guard candidates.count == 1, let candidate = candidates.first else { throw SpeechSetupError.invalidModelFiles }
        return candidate
    }

    private static func validate(_ model: SherpaModel, in folder: URL) throws {
        let required: [[String]]
        switch model.modelType {
        case "vits":
            guard hasLexicon(in: folder),
                  contents(of: folder).contains(where: { $0.pathExtension == "onnx" && contains($0.lastPathComponent, in: folder) }) else {
                throw SpeechSetupError.invalidModelFiles
            }
            required = [["tokens.txt"]]
        case "mms":
            required = [["model.onnx"], ["tokens.txt"]]
        case "kokoro", "kitten":
            guard hasLexicon(in: folder) else { throw SpeechSetupError.modelNeedsLexicon }
            required = [["model.onnx", "model.int8.onnx"], ["tokens.txt"], ["voices.bin"]]
        case "supertonic":
            required = ["duration_predictor", "text_encoder", "vector_estimator", "vocoder"].map {
                ["\($0).onnx", "\($0).int8.onnx"]
            } + [["tts.json"], ["unicode_indexer.bin"], ["voice.bin"]]
        case "matcha":
            required = [
                ["acoustic-model.onnx", "model-steps-3.onnx", "model-steps-1000.onnx", "model.onnx"],
                ["tokens.txt"], ["lexicon.txt"], ["vocoder.onnx"],
            ]
        case "zipvoice":
            required = [
                ["encoder.onnx", "encoder.int8.onnx"], ["decoder.onnx", "decoder.int8.onnx"],
                ["tokens.txt"], ["lexicon.txt"], ["vocoder.onnx"], ["test_wavs/leijun-1.wav"],
            ]
        case "pocket":
            let hasReference = contents(of: folder.appending(path: "test_wavs")).contains { $0.pathExtension == "wav" }
                || contents(of: folder).contains { $0.pathExtension == "wav" }
            guard hasReference else { throw SpeechSetupError.invalidModelFiles }
            required = ["lm_flow", "lm_main", "encoder", "decoder", "text_conditioner"].map {
                ["\($0).onnx", "\($0).int8.onnx"]
            } + [["vocab.json"], ["token_scores.json"]]
        default:
            throw SpeechSetupError.invalidModelFiles
        }
        guard required.allSatisfy({ group in group.contains { contains($0, in: folder) } }) else {
            throw SpeechSetupError.invalidModelFiles
        }
    }
    #endif

    static func importFile(from source: URL) throws -> String {
        let scoped = source.startAccessingSecurityScopedResource()
        defer { if scoped { source.stopAccessingSecurityScopedResource() } }
        guard try source.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true else {
            throw SpeechSetupError.credentialFileRequired
        }
        let relative = "Files/\(UUID().uuidString)/\(source.lastPathComponent)"
        let destination = root.appending(path: relative)
        try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: source, to: destination)
        return relative
    }
}

enum SpeechSetupError: LocalizedError {
    case credentialFileRequired
    case modelNotInstalled
    case modelDownloadFailed
    case modelNeedsLexicon
    case invalidModelFiles
    case playbackFailed

    var errorDescription: String? {
        switch self {
        case .credentialFileRequired: String(localized: "Choose a credentials file.")
        case .modelNotInstalled: String(localized: "Download a speech model before speaking.")
        case .modelDownloadFailed: String(localized: "Could not download or verify the speech model.")
        case .modelNeedsLexicon: String(localized: "This model needs a pronunciation dictionary that Dasher cannot install yet.")
        case .invalidModelFiles: String(localized: "The downloaded model is missing files required by Sherpa-ONNX.")
        case .playbackFailed: String(localized: "Could not play the synthesized audio.")
        }
    }
}
