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

    static func isValidModelID(_ modelID: String) -> Bool {
        modelID.range(of: "^[A-Za-z0-9][A-Za-z0-9_.-]*$", options: .regularExpression) != nil
    }

    static func hasModel(_ modelID: String) -> Bool {
        isValidModelID(modelID) && containsModelFiles(at: models.appending(path: modelID))
    }

    static func installModel(from source: URL, as modelID: String) throws {
        guard isValidModelID(modelID) else { throw SpeechSetupError.invalidModelID }
        let scoped = source.startAccessingSecurityScopedResource()
        defer { if scoped { source.stopAccessingSecurityScopedResource() } }
        guard try source.resourceValues(forKeys: [.isDirectoryKey]).isDirectory == true else {
            throw SpeechSetupError.modelFolderRequired
        }
        let manager = FileManager.default
        let staging = models.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try manager.createDirectory(at: models, withIntermediateDirectories: true)
        defer { try? manager.removeItem(at: staging) }
        try manager.copyItem(at: source, to: staging)
        guard containsModelFiles(at: staging) else { throw SpeechSetupError.modelFilesMissing }
        try validateTokenFiles(in: staging)
        try commitModel(at: staging, as: modelID)
    }

    private static func containsModelFiles(at directory: URL) -> Bool {
        let manager = FileManager.default
        guard let contents = try? manager.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.isRegularFileKey, .isDirectoryKey]) else {
            return false
        }
        return contents.contains { file in
            file.pathExtension == "onnx" && (try? file.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true
        } || contents.contains { file in
            guard (try? file.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true,
                  let files = try? manager.contentsOfDirectory(atPath: file.path) else { return false }
            return files.contains { $0.hasSuffix(".onnx") }
        }
    }

    private static func validateTokenFiles(in directory: URL) throws {
        let manager = FileManager.default
        let children = try manager.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.isDirectoryKey])
        let directories = [directory] + children.filter {
            (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
        }
        for folder in directories {
            let file = folder.appending(path: "tokens.txt")
            guard manager.fileExists(atPath: file.path) else { continue }
            let tokens = try String(contentsOf: file, encoding: .utf8)
            var symbols = Set<String>()
            for line in tokens.split(whereSeparator: \.isNewline) {
                let fields = line.split(whereSeparator: \.isWhitespace)
                guard let rawID = fields.last, let id = Int32(rawID), id >= 0, fields.count <= 2 else {
                    throw SpeechSetupError.modelTokensInvalid
                }
                let symbol = fields.count == 1 ? " " : String(fields[0])
                guard symbols.insert(symbol).inserted else { throw SpeechSetupError.modelTokensInvalid }
            }
            guard !symbols.isEmpty else { throw SpeechSetupError.modelTokensInvalid }
        }
    }

    private static func commitModel(at staging: URL, as modelID: String, in directory: URL = models) throws {
        let manager = FileManager.default
        let destination = directory.appending(path: modelID, directoryHint: .isDirectory)
        if manager.fileExists(atPath: destination.path) {
            _ = try manager.replaceItemAt(destination, withItemAt: staging)
        } else {
            try manager.moveItem(at: staging, to: destination)
        }
        var installed = destination
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? installed.setResourceValues(values)
    }

    #if os(macOS) || os(iOS)
    static let englishModelID = "inflect-en-nano-v2"
    private static let modelRelease = URL(string: "https://github.com/k2-fsa/sherpa-onnx/releases/download/tts-models/")!

    static func downloadEnglishModel(to directory: URL = models) async throws {
        let archiveName = "vits-\(englishModelID)"
        async let archive = downloadModelAsset(
            "\(archiveName).tar.bz2",
            sha256: "9a6b1188b5f3be8813e0552056328495b4e88ffd1ef18ff837272bde7b3bc136"
        )
        async let lexicon = downloadModelAsset(
            "lexicon-en-us.txt",
            sha256: "8b67ae549a465eee78f92ecb74644ad90c3c58ce65f19c68baf85878a10ef73a"
        )
        try await installEnglishArchive(archive, lexicon: lexicon, archiveName: archiveName, in: directory)
    }

    private static func downloadModelAsset(_ name: String, sha256: String) async throws -> Data {
        let (download, response) = try await URLSession.shared.download(from: modelRelease.appending(path: name))
        defer { try? FileManager.default.removeItem(at: download) }
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw SpeechSetupError.modelDownloadFailed }
        let data = try Data(contentsOf: download, options: .mappedIfSafe)
        let checksum = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        guard checksum == sha256 else { throw SpeechSetupError.modelDownloadFailed }
        return data
    }

    private static func decompressModelArchive(_ archive: Data) throws -> Data {
        // The pinned English archive expands to less than 64 MiB.
        var outputSize: UInt32 = 64 * 1024 * 1024
        var output = Data(count: Int(outputSize))
        var input = archive
        let result = output.withUnsafeMutableBytes { destination in
            input.withUnsafeMutableBytes { source in
                BZ2_bzBuffToBuffDecompress(
                    destination.bindMemory(to: CChar.self).baseAddress, &outputSize,
                    source.bindMemory(to: CChar.self).baseAddress, UInt32(source.count), 0, 0
                )
            }
        }
        guard result == BZ_OK else { throw SpeechSetupError.modelDownloadFailed }
        output.count = Int(outputSize)
        return output
    }

    private static func installEnglishArchive(_ archive: Data, lexicon: Data, archiveName: String, in directory: URL) throws {
        let manager = FileManager.default
        let staging = directory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try manager.createDirectory(at: staging, withIntermediateDirectories: true)
        defer { try? manager.removeItem(at: staging) }

        let tar = try decompressModelArchive(archive)
        for entry in try TarContainer.open(container: tar) {
            guard let data = entry.data else { continue }
            let parts = entry.info.name.split(separator: "/", omittingEmptySubsequences: false)
            guard let archiveRoot = parts.first, archiveRoot == archiveName, parts.count > 1,
                  parts.dropFirst().allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." }) else {
                throw SpeechSetupError.modelDownloadFailed
            }
            let file = staging.appending(path: parts.dropFirst().joined(separator: "/"))
            try manager.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: file)
        }
        try lexicon.write(to: staging.appending(path: "lexicon.txt"))
        guard containsModelFiles(at: staging) else { throw SpeechSetupError.modelFilesMissing }
        try commitModel(at: staging, as: englishModelID, in: directory)
    }
    #endif

    static func importFile(from source: URL) throws -> String {
        let scoped = source.startAccessingSecurityScopedResource()
        defer { if scoped { source.stopAccessingSecurityScopedResource() } }
        let relative = "Files/\(UUID().uuidString)/\(source.lastPathComponent)"
        let destination = root.appending(path: relative)
        try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: source, to: destination)
        return relative
    }
}

enum SpeechSetupError: LocalizedError {
    case invalidModelID
    case modelFolderRequired
    case modelFilesMissing
    case modelTokensInvalid
    case modelNotInstalled
    case modelDownloadFailed
    case playbackFailed

    var errorDescription: String? {
        switch self {
        case .invalidModelID: String(localized: "Enter a valid Sherpa-ONNX model ID.")
        case .modelFolderRequired: String(localized: "Choose the extracted Sherpa-ONNX model folder.")
        case .modelFilesMissing: String(localized: "The folder does not contain an ONNX model file.")
        case .modelTokensInvalid: String(localized: "The Sherpa-ONNX model has an invalid tokens.txt file.")
        case .modelNotInstalled: String(localized: "Import the Sherpa-ONNX model folder before speaking.")
        case .modelDownloadFailed: String(localized: "Could not download or verify the English speech model.")
        case .playbackFailed: String(localized: "Could not play the synthesized audio.")
        }
    }
}
