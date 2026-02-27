import Foundation

enum LocalWhisperInstallerError: LocalizedError {
    case brewNotFound
    case whisperBinaryNotFound
    case processFailed(String)
    case downloadFailed(String)

    var errorDescription: String? {
        switch self {
        case .brewNotFound:
            "Homebrew не найден. Установите Homebrew или укажите путь к whisper-cli вручную."
        case .whisperBinaryNotFound:
            "Не удалось найти whisper-cli после установки."
        case .processFailed(let details):
            "Ошибка установки whisper: \(details)"
        case .downloadFailed(let details):
            "Ошибка скачивания модели: \(details)"
        }
    }
}

struct LocalWhisperStatus {
    var whisperReady: Bool
    var fastModelReady: Bool
    var accurateModelReady: Bool

    var isReady: Bool {
        whisperReady && fastModelReady && accurateModelReady
    }

    var missingItemsDescription: String {
        var parts: [String] = []
        if !whisperReady { parts.append("whisper-cli") }
        if !fastModelReady { parts.append("fast модель") }
        if !accurateModelReady { parts.append("accurate модель") }
        return parts.joined(separator: ", ")
    }
}

final class LocalWhisperInstaller: @unchecked Sendable {
    private let logger: AppLogger
    private let session: URLSession

    init(logger: AppLogger = .shared, session: URLSession = .shared) {
        self.logger = logger
        self.session = session
    }

    func status(for settings: AppSettings) -> LocalWhisperStatus {
        LocalWhisperStatus(
            whisperReady: detectWhisperPath(preferredPath: settings.whisperCLIPath) != nil,
            fastModelReady: FileManager.default.fileExists(atPath: settings.fastModelPath),
            accurateModelReady: FileManager.default.fileExists(atPath: settings.accurateModelPath)
        )
    }

    func ensureInstalled(
        settings: AppSettings,
        allowBrewInstall: Bool
    ) async throws -> AppSettings {
        var updated = settings

        var whisperPath = detectWhisperPath(preferredPath: updated.whisperCLIPath)

        if whisperPath == nil && allowBrewInstall {
            try await installWhisperWithBrew()
            whisperPath = detectWhisperPath(preferredPath: updated.whisperCLIPath)
        }

        guard let whisperPath else {
            throw LocalWhisperInstallerError.whisperBinaryNotFound
        }

        updated.whisperCLIPath = whisperPath

        try await ensureModel(
            destinationPath: updated.fastModelPath,
            remoteURL: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-base.bin",
            progressMessage: "Скачиваю fast модель (ggml-base.bin)..."
        )

        try await ensureModel(
            destinationPath: updated.accurateModelPath,
            remoteURL: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-medium.bin",
            progressMessage: "Скачиваю accurate модель (ggml-medium.bin)..."
        )

        logger.info("Local whisper setup complete")
        return updated
    }

    func detectWhisperPath(preferredPath: String) -> String? {
        let candidates = [
            preferredPath,
            "/opt/homebrew/bin/whisper-cli",
            "/usr/local/bin/whisper-cli"
        ]

        for candidate in candidates where !candidate.isEmpty {
            if FileManager.default.isExecutableFile(atPath: candidate) {
                return candidate
            }
        }

        if let discovered = try? runProcessSync(
            executable: "/usr/bin/which",
            arguments: ["whisper-cli"]
        ).trimmingCharacters(in: .whitespacesAndNewlines),
           !discovered.isEmpty,
           FileManager.default.isExecutableFile(atPath: discovered) {
            return discovered
        }

        return nil
    }

    private func installWhisperWithBrew() async throws {
        let brewPath = detectBrewPath()
        guard let brewPath else {
            throw LocalWhisperInstallerError.brewNotFound
        }

        _ = try await runProcessAsync(executable: brewPath, arguments: ["install", "whisper-cpp"])
    }

    private func ensureModel(
        destinationPath: String,
        remoteURL: String,
        progressMessage: String
    ) async throws {
        if FileManager.default.fileExists(atPath: destinationPath) {
            return
        }

        let destinationURL = URL(fileURLWithPath: destinationPath)
        let destinationDir = destinationURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: destinationDir, withIntermediateDirectories: true)

        guard let url = URL(string: remoteURL) else {
            throw LocalWhisperInstallerError.downloadFailed("Некорректный URL")
        }

        logger.info(progressMessage)
        do {
            let (temporaryFileURL, response) = try await session.download(from: url)
            guard let httpResponse = response as? HTTPURLResponse,
                  (200..<300).contains(httpResponse.statusCode) else {
                throw LocalWhisperInstallerError.downloadFailed("HTTP ошибка")
            }

            if FileManager.default.fileExists(atPath: destinationPath) {
                try FileManager.default.removeItem(atPath: destinationPath)
            }
            try FileManager.default.moveItem(at: temporaryFileURL, to: destinationURL)
        } catch {
            throw LocalWhisperInstallerError.downloadFailed(error.localizedDescription)
        }
    }

    private func detectBrewPath() -> String? {
        let candidates = [
            "/opt/homebrew/bin/brew",
            "/usr/local/bin/brew"
        ]

        for candidate in candidates {
            if FileManager.default.isExecutableFile(atPath: candidate) {
                return candidate
            }
        }

        if let discovered = try? runProcessSync(
            executable: "/usr/bin/which",
            arguments: ["brew"]
        ).trimmingCharacters(in: .whitespacesAndNewlines),
           !discovered.isEmpty,
           FileManager.default.isExecutableFile(atPath: discovered) {
            return discovered
        }

        return nil
    }

    private func runProcessAsync(executable: String, arguments: [String]) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let result = try self.runProcessSync(executable: executable, arguments: arguments)
                    continuation.resume(returning: result)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private func runProcessSync(executable: String, arguments: [String]) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments

        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            throw LocalWhisperInstallerError.processFailed(error.localizedDescription)
        }

        let output = String(data: outputPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let stderr = String(data: errorPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""

        guard process.terminationStatus == 0 else {
            let details = stderr.isEmpty ? output : stderr
            throw LocalWhisperInstallerError.processFailed(details.trimmingCharacters(in: .whitespacesAndNewlines))
        }

        return output
    }
}
