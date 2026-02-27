import Foundation

enum AppPaths {
    static let appFolderName = "LocalKiklet"

    static var appSupportDirectory: URL {
        let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let folder = root.appendingPathComponent(appFolderName, isDirectory: true)
        ensureDirectory(folder)
        return folder
    }

    static var modelsDirectory: URL {
        let folder = appSupportDirectory.appendingPathComponent("models", isDirectory: true)
        ensureDirectory(folder)
        return folder
    }

    static var logsDirectory: URL {
        let folder = appSupportDirectory.appendingPathComponent("logs", isDirectory: true)
        ensureDirectory(folder)
        return folder
    }

    static var settingsFile: URL {
        appSupportDirectory.appendingPathComponent("settings.json")
    }

    static var historyFile: URL {
        appSupportDirectory.appendingPathComponent("history.json")
    }

    static var logFile: URL {
        logsDirectory.appendingPathComponent("localkiklet.log")
    }

    private static func ensureDirectory(_ url: URL) {
        if !FileManager.default.fileExists(atPath: url.path) {
            try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        }
    }
}
