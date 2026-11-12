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

    static func hasEnglishModel(in directory: URL = models) -> Bool {
        let model = directory.appending(path: englishModelID, directoryHint: .isDirectory)
        return containsEnglishModelFiles(at: model)
    }

    private static func containsEnglishModelFiles(at directory: URL) -> Bool {
        ["model.onnx", "tokens.txt", "lexicon.txt"].allSatisfy { name in
            let file = directory.appending(path: name)
            guard let values = try? file.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]) else {
                return false
            }
            return values.isRegularFile == true && (values.fileSize ?? 0) > 0
        }
    }

    private static func commitEnglishModel(at staging: URL, in directory: URL) throws {
        let manager = FileManager.default
        let destination = directory.appending(path: englishModelID, directoryHint: .isDirectory)
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
        guard containsEnglishModelFiles(at: staging) else { throw SpeechSetupError.modelDownloadFailed }
        try commitEnglishModel(at: staging, in: directory)
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
    case playbackFailed

    var errorDescription: String? {
        switch self {
        case .credentialFileRequired: String(localized: "Choose a credentials file.")
        case .modelNotInstalled: String(localized: "Set up the English voice before speaking.")
        case .modelDownloadFailed: String(localized: "Could not download or verify the English speech model.")
        case .playbackFailed: String(localized: "Could not play the synthesized audio.")
        }
    }
}
