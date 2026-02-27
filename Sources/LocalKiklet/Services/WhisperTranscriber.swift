import Foundation

enum TranscriptionError: LocalizedError {
    case missingBinary(String)
    case missingModel(String)
    case processFailed(String)
    case cancelled
    case emptyResult
    case timedOut

    var errorDescription: String? {
        switch self {
        case .missingBinary(let path):
            "Не найден whisper-cli: \(path). Укажите корректный путь в настройках."
        case .missingModel(let path):
            "Не найдена модель: \(path). Скачайте модель и обновите путь в настройках."
        case .processFailed(let message):
            "Ошибка локальной модели: \(message)"
        case .cancelled:
            "Транскрибация отменена."
        case .emptyResult:
            "Локальная модель вернула пустой результат."
        case .timedOut:
            "Транскрибация заняла слишком много времени и была остановлена."
        }
    }
}

final class WhisperTranscriber: @unchecked Sendable {
    private let logger: AppLogger
    private let lock = NSLock()
    private var currentProcess: Process?

    init(logger: AppLogger = .shared) {
        self.logger = logger
    }

    func transcribe(audioURL: URL, settings: AppSettings, timeout: TimeInterval = 180) async throws -> String {
        let binaryPath = settings.whisperCLIPath
        guard FileManager.default.isExecutableFile(atPath: binaryPath) else {
            throw TranscriptionError.missingBinary(binaryPath)
        }

        let modelPath = settings.modelPath
        guard FileManager.default.fileExists(atPath: modelPath) else {
            throw TranscriptionError.missingModel(modelPath)
        }

        let preparedAudioURL = try prepareAudioFileForWhisper(audioURL)
        let shouldDeletePrepared = preparedAudioURL != audioURL

        return try await withTaskCancellationHandler(operation: {
            defer {
                if shouldDeletePrepared {
                    try? FileManager.default.removeItem(at: preparedAudioURL)
                }
            }
            return try await withThrowingTaskGroup(of: String.self) { group in
                group.addTask {
                    do {
                        return try await self.runWhisper(
                            audioURL: preparedAudioURL,
                            binaryPath: binaryPath,
                            modelPath: modelPath,
                            language: settings.recognitionLanguage
                        )
                    } catch TranscriptionError.emptyResult where settings.recognitionLanguage != "auto" {
                        self.logger.warn("Whisper returned empty result with language=\(settings.recognitionLanguage), retry with auto")
                        return try await self.runWhisper(
                            audioURL: preparedAudioURL,
                            binaryPath: binaryPath,
                            modelPath: modelPath,
                            language: "auto"
                        )
                    }
                }

                group.addTask {
                    try await Task.sleep(for: .seconds(timeout))
                    self.cancel()
                    throw TranscriptionError.timedOut
                }

                guard let first = try await group.next() else {
                    throw TranscriptionError.emptyResult
                }
                group.cancelAll()
                return first
            }
        }, onCancel: {
            self.cancel()
        })
    }

    func cancel() {
        lock.lock()
        defer { lock.unlock() }
        currentProcess?.terminate()
        currentProcess = nil
        logger.warn("Transcription cancelled")
    }

    private func runWhisper(audioURL: URL, binaryPath: String, modelPath: String, language: String) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            let outputPipe = Pipe()
            let errorPipe = Pipe()
            process.executableURL = URL(fileURLWithPath: binaryPath)
            let outputPrefixURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("localkiklet-whisper-\(UUID().uuidString)")

            let args = [
                "-m", modelPath,
                "-f", audioURL.path,
                "-nt",
                "-nth", "0.35",
                "-otxt",
                "-of", outputPrefixURL.path,
                "-l", language
            ]
            process.arguments = args
            process.standardOutput = outputPipe
            process.standardError = errorPipe

            lock.lock()
            currentProcess = process
            lock.unlock()

            let startedAt = Date()
            process.terminationHandler = { [weak self] proc in
                guard let self else { return }
                self.lock.lock()
                self.currentProcess = nil
                self.lock.unlock()

                let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
                let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
                let outputText = String(data: outputData, encoding: .utf8) ?? ""
                let stderrText = String(data: errorData, encoding: .utf8) ?? ""
                let elapsed = Date().timeIntervalSince(startedAt)
                let transcriptFileURL = outputPrefixURL.appendingPathExtension("txt")
                let transcriptRaw = try? String(contentsOf: transcriptFileURL, encoding: .utf8)
                let transcriptFromFile = transcriptRaw?.trimmingCharacters(in: .whitespacesAndNewlines)
                Self.cleanupOutputFiles(prefixURL: outputPrefixURL)

                if proc.terminationStatus != 0 {
                    if proc.terminationReason == .uncaughtSignal {
                        continuation.resume(throwing: TranscriptionError.cancelled)
                        return
                    }
                    continuation.resume(throwing: TranscriptionError.processFailed(stderrText.isEmpty ? outputText : stderrText))
                    return
                }

                let parsed: String
                if let transcriptFromFile, !transcriptFromFile.isEmpty {
                    parsed = transcriptFromFile
                } else {
                    parsed = Self.extractTranscript(from: outputText)
                }
                guard !parsed.isEmpty else {
                    let stderrSnippet = Self.truncatedLogSnippet(stderrText)
                    let outputSnippet = Self.truncatedLogSnippet(outputText)
                    if !stderrSnippet.isEmpty || !outputSnippet.isEmpty {
                        self.logger.warn("Whisper empty result. stderr=\(stderrSnippet) stdout=\(outputSnippet)")
                    } else {
                        self.logger.warn("Whisper empty result without stderr/stdout output")
                    }
                    continuation.resume(throwing: TranscriptionError.emptyResult)
                    return
                }

                self.logger.info("Transcription finished in \(String(format: "%.2f", elapsed))s")
                continuation.resume(returning: parsed)
            }

            do {
                try process.run()
                logger.info("Whisper started with model \(modelPath)")
            } catch {
                lock.lock()
                currentProcess = nil
                lock.unlock()
                Self.cleanupOutputFiles(prefixURL: outputPrefixURL)
                continuation.resume(throwing: TranscriptionError.processFailed(error.localizedDescription))
            }
        }
    }

    private static func extractTranscript(from raw: String) -> String {
        let lines = raw
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .filter { !$0.hasPrefix("[") }

        if lines.isEmpty {
            return raw.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return lines.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func cleanupOutputFiles(prefixURL: URL) {
        let extensions = ["txt", "vtt", "srt", "csv", "json", "wts"]
        for ext in extensions {
            let url = prefixURL.appendingPathExtension(ext)
            if FileManager.default.fileExists(atPath: url.path) {
                try? FileManager.default.removeItem(at: url)
            }
        }
    }

    private static func truncatedLogSnippet(_ text: String, limit: Int = 240) -> String {
        let compact = text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\n", with: " ")
        if compact.count <= limit {
            return compact
        }
        return "\(compact.prefix(limit - 1))…"
    }

    private func prepareAudioFileForWhisper(_ inputURL: URL) throws -> URL {
        let ext = inputURL.pathExtension.lowercased()
        if ext == "wav" {
            return inputURL
        }

        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("localkiklet-whisper-input-\(UUID().uuidString)")
            .appendingPathExtension("wav")

        let conversionArgs = [
            "-f", "WAVE",
            "-d", "LEI16@16000",
            "-c", "1",
            inputURL.path,
            outputURL.path
        ]

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/afconvert")
        process.arguments = conversionArgs

        let stderrPipe = Pipe()
        process.standardError = stderrPipe
        process.standardOutput = Pipe()

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            throw TranscriptionError.processFailed("Не удалось запустить afconvert: \(error.localizedDescription)")
        }

        guard process.terminationStatus == 0 else {
            let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
            let stderrText = String(data: stderrData, encoding: .utf8) ?? ""
            throw TranscriptionError.processFailed("Конвертация в WAV не удалась: \(stderrText)")
        }

        logger.info("Audio converted for whisper: \(inputURL.lastPathComponent) -> \(outputURL.lastPathComponent)")
        return outputURL
    }
}
