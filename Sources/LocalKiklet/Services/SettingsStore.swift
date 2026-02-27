import Foundation

@MainActor
final class SettingsStore: ObservableObject {
    @Published var settings: AppSettings {
        didSet {
            guard !isLoading else { return }
            save()
        }
    }

    private let fileURL: URL
    private var isLoading = false
    private let logger: AppLogger

    init(fileURL: URL = AppPaths.settingsFile, logger: AppLogger = .shared) {
        self.fileURL = fileURL
        self.logger = logger
        if let loaded = Self.loadFromDisk(fileURL: fileURL) {
            self.settings = loaded
        } else {
            self.settings = .default
        }
        save()
    }

    func upsertCustomAction(_ action: TextAction) {
        var normalized = action
        if BuiltInActions.isBuiltIn(id: action.id) {
            normalized.isBuiltIn = true
        }

        var actions = settings.customActions
        if let idx = actions.firstIndex(where: { $0.id == normalized.id }) {
            actions[idx] = normalized
        } else {
            actions.append(normalized)
        }
        settings.customActions = actions
    }

    func removeCustomAction(id: String) {
        settings.customActions.removeAll { $0.id == id }
        if settings.action(by: settings.defaultActionID) == nil {
            settings.defaultActionID = BuiltInActions.passthroughID
        }
    }

    func resetBuiltInAction(id: String) {
        guard BuiltInActions.isBuiltIn(id: id) else { return }
        settings.customActions.removeAll { $0.id == id }
    }

    func duplicateAction(id: String) {
        guard let source = settings.customActions.first(where: { $0.id == id }) ?? BuiltInActions.all.first(where: { $0.id == id }) else {
            return
        }
        var clone = source
        clone.id = UUID().uuidString
        clone.isBuiltIn = false
        clone.name = "\(source.name) (копия)"
        settings.customActions.append(clone)
    }

    func resetOnboarding() {
        settings.onboardingCompleted = false
    }

    private func save() {
        do {
            let data = try JSONEncoder.settingsEncoder.encode(settings)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            logger.error("Failed to save settings: \(error.localizedDescription)")
        }
    }

    private static func loadFromDisk(fileURL: URL) -> AppSettings? {
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        return try? JSONDecoder.settingsDecoder.decode(AppSettings.self, from: data)
    }
}

private extension JSONEncoder {
    static var settingsEncoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }
}

private extension JSONDecoder {
    static var settingsDecoder: JSONDecoder {
        JSONDecoder()
    }
}
