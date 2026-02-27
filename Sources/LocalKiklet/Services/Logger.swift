import Foundation

final class AppLogger: @unchecked Sendable {
    static let shared = AppLogger()

    enum Level: String {
        case info
        case warn
        case error
    }

    private let queue = DispatchQueue(label: "localkiklet.logger")
    private let formatter: ISO8601DateFormatter
    private let fileURL: URL

    private init(fileURL: URL = AppPaths.logFile) {
        self.fileURL = fileURL
        self.formatter = ISO8601DateFormatter()
        ensureLogFile()
    }

    func info(_ message: String) { log(.info, message) }
    func warn(_ message: String) { log(.warn, message) }
    func error(_ message: String) { log(.error, message) }

    func exportLogs(to destinationURL: URL) throws {
        try FileManager.default.copyItem(at: fileURL, to: destinationURL)
    }

    var logPath: String {
        fileURL.path
    }

    private func ensureLogFile() {
        if !FileManager.default.fileExists(atPath: fileURL.path) {
            FileManager.default.createFile(atPath: fileURL.path, contents: Data())
        }
    }

    private func log(_ level: Level, _ message: String) {
        queue.async {
            self.ensureLogFile()
            let line = "[\(self.formatter.string(from: Date()))] [\(level.rawValue.uppercased())] \(message)\n"
            guard let data = line.data(using: .utf8) else { return }
            guard let handle = try? FileHandle(forWritingTo: self.fileURL) else { return }
            do {
                try handle.seekToEnd()
                try handle.write(contentsOf: data)
                try handle.close()
            } catch {
                try? handle.close()
            }
        }
    }
}
