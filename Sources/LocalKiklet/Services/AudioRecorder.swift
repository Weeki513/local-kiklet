import AVFoundation
import Foundation

enum AudioRecorderError: LocalizedError {
    case alreadyRecording
    case notRecording
    case inputUnavailable

    var errorDescription: String? {
        switch self {
        case .alreadyRecording:
            "Запись уже идёт."
        case .notRecording:
            "Запись не запущена."
        case .inputUnavailable:
            "Устройство ввода не доступно."
        }
    }
}

final class AudioRecorder {
    private let engine = AVAudioEngine()
    private var currentFile: AVAudioFile?
    private var currentURL: URL?
    private let logger: AppLogger

    private(set) var isRecording = false

    init(logger: AppLogger = .shared) {
        self.logger = logger
    }

    func start() throws {
        guard !isRecording else { throw AudioRecorderError.alreadyRecording }
        guard engine.inputNode.inputFormat(forBus: 0).sampleRate > 0 else {
            throw AudioRecorderError.inputUnavailable
        }

        let url = Self.makeRecordingURL()
        let inputNode = engine.inputNode
        let format = inputNode.outputFormat(forBus: 0)
        let file = try AVAudioFile(forWriting: url, settings: format.settings)

        inputNode.removeTap(onBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 2048, format: format) { [weak self] buffer, _ in
            guard let self, let currentFile = self.currentFile else { return }
            do {
                try currentFile.write(from: buffer)
            } catch {
                self.logger.error("Audio write failed: \(error.localizedDescription)")
            }
        }

        currentFile = file
        currentURL = url
        engine.prepare()
        try engine.start()
        isRecording = true
        logger.info("Recording started")
    }

    func stop() throws -> URL {
        guard isRecording else { throw AudioRecorderError.notRecording }
        engine.stop()
        engine.inputNode.removeTap(onBus: 0)
        isRecording = false

        defer {
            currentFile = nil
            currentURL = nil
        }

        guard let url = currentURL else {
            throw AudioRecorderError.notRecording
        }
        logger.info("Recording stopped: \(url.lastPathComponent)")
        return url
    }

    private static func makeRecordingURL() -> URL {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let timestamp = formatter.string(from: Date()).replacingOccurrences(of: ":", with: "-")
        return FileManager.default.temporaryDirectory
            .appendingPathComponent("localkiklet-\(timestamp)")
            .appendingPathExtension("caf")
    }
}
