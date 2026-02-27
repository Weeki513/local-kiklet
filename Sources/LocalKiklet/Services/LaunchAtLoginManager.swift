import Darwin
import Foundation
import ServiceManagement

enum LaunchAtLoginState {
    case enabled
    case enabledViaLaunchAgent
    case requiresApproval
    case disabled
    case unavailable

    var isOnForToggle: Bool {
        switch self {
        case .enabled, .enabledViaLaunchAgent, .requiresApproval:
            true
        case .disabled, .unavailable:
            false
        }
    }

    var hint: String? {
        switch self {
        case .enabled:
            "Автозапуск включён"
        case .enabledViaLaunchAgent:
            "Автозапуск включён (через LaunchAgent)"
        case .requiresApproval:
            "Ожидает подтверждения в System Settings -> Login Items"
        case .disabled:
            "Автозапуск выключен"
        case .unavailable:
            "Недоступно для текущего запуска. Проверьте, что приложение запущено из .app"
        }
    }
}

enum LaunchAtLoginError: LocalizedError {
    case notAvailable
    case permissionDenied
    case failed(String)

    var errorDescription: String? {
        switch self {
        case .notAvailable:
            "Автозапуск недоступен. Запускайте приложение из установленного .app"
        case .permissionDenied:
            "macOS отклонил изменение автозапуска. Разрешите в Login Items"
        case .failed(let message):
            "Не удалось изменить автозапуск: \(message)"
        }
    }
}

@MainActor
final class LaunchAtLoginManager {
    private let logger: AppLogger
    private let fileManager: FileManager
    private let launchAgentLabel = "dev.localkiklet.launchagent"

    init(logger: AppLogger = .shared, fileManager: FileManager = .default) {
        self.logger = logger
        self.fileManager = fileManager
    }

    func currentState() -> LaunchAtLoginState {
        if isLaunchAgentEnabled() {
            return .enabledViaLaunchAgent
        }

        switch SMAppService.mainApp.status {
        case .enabled:
            return .enabled
        case .requiresApproval:
            return .requiresApproval
        case .notRegistered:
            return .disabled
        case .notFound:
            return isBundleLaunchable ? .disabled : .unavailable
        @unknown default:
            return .disabled
        }
    }

    func setEnabled(_ enabled: Bool) throws {
        guard isBundleLaunchable else {
            throw LaunchAtLoginError.notAvailable
        }

        if enabled {
            try enableAutostart()
        } else {
            try disableAutostart()
        }
    }

    private var isBundleLaunchable: Bool {
        Bundle.main.bundleURL.pathExtension.lowercased() == "app"
    }

    private func enableAutostart() throws {
        do {
            try SMAppService.mainApp.register()
            try disableLaunchAgentIfPresent()
            return
        } catch {
            logger.warn("SMAppService register failed, fallback to LaunchAgent: \(error.localizedDescription)")
        }

        do {
            try enableLaunchAgent()
        } catch {
            throw LaunchAtLoginError.failed(error.localizedDescription)
        }

        if !currentState().isOnForToggle {
            throw LaunchAtLoginError.permissionDenied
        }
    }

    private func disableAutostart() throws {
        var failures: [String] = []

        do {
            try SMAppService.mainApp.unregister()
        } catch {
            logger.warn("SMAppService unregister failed: \(error.localizedDescription)")
            failures.append(error.localizedDescription)
        }

        do {
            try disableLaunchAgentIfPresent()
        } catch {
            logger.warn("LaunchAgent disable failed: \(error.localizedDescription)")
            failures.append(error.localizedDescription)
        }

        if currentState().isOnForToggle {
            let details = failures.joined(separator: " | ")
            throw LaunchAtLoginError.failed(details.isEmpty ? "не удалось отключить" : details)
        }
    }

    private func enableLaunchAgent() throws {
        let launchAgentsDir = launchAgentURL.deletingLastPathComponent()
        try fileManager.createDirectory(at: launchAgentsDir, withIntermediateDirectories: true)

        let plist: [String: Any] = [
            "Label": launchAgentLabel,
            "ProgramArguments": ["/usr/bin/open", Bundle.main.bundleURL.path],
            "RunAtLoad": true,
            "KeepAlive": false,
            "LimitLoadToSessionType": ["Aqua"],
            "ProcessType": "Interactive"
        ]

        let plistData = try PropertyListSerialization.data(
            fromPropertyList: plist,
            format: .xml,
            options: 0
        )
        try plistData.write(to: launchAgentURL, options: .atomic)

        // Ensure we refresh an existing loaded job with the new path.
        _ = try? runLaunchctl(arguments: ["bootout", "gui/\(getuid())", launchAgentURL.path])
        do {
            _ = try runLaunchctl(arguments: ["bootstrap", "gui/\(getuid())", launchAgentURL.path])
        } catch {
            // Fallback for systems where bootstrap is unavailable.
            _ = try runLaunchctl(arguments: ["load", launchAgentURL.path])
        }
    }

    private func disableLaunchAgentIfPresent() throws {
        _ = try? runLaunchctl(arguments: ["bootout", "gui/\(getuid())", launchAgentURL.path])
        _ = try? runLaunchctl(arguments: ["remove", launchAgentLabel])
        _ = try? runLaunchctl(arguments: ["unload", launchAgentURL.path])

        if fileManager.fileExists(atPath: launchAgentURL.path) {
            try fileManager.removeItem(at: launchAgentURL)
        }
    }

    private func isLaunchAgentEnabled() -> Bool {
        if fileManager.fileExists(atPath: launchAgentURL.path) {
            return true
        }
        return (try? runLaunchctl(arguments: ["print", "gui/\(getuid())/\(launchAgentLabel)"])) != nil
    }

    private var launchAgentURL: URL {
        fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("LaunchAgents", isDirectory: true)
            .appendingPathComponent("\(launchAgentLabel).plist")
    }

    @discardableResult
    private func runLaunchctl(arguments: [String]) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = arguments

        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe

        try process.run()
        process.waitUntilExit()

        let output = String(data: outPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let error = String(data: errPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""

        guard process.terminationStatus == 0 else {
            let details = (error.isEmpty ? output : error).trimmingCharacters(in: .whitespacesAndNewlines)
            throw LaunchAtLoginError.failed(details.isEmpty ? "launchctl exited with code \(process.terminationStatus)" : details)
        }

        return output
    }
}
