import Foundation

enum OutputMode: String, Codable, CaseIterable, Identifiable {
    case smart
    case alwaysInput
    case alwaysClipboard

    var id: String { rawValue }

    var title: String {
        switch self {
        case .smart: "Умный режим"
        case .alwaysInput: "Всегда вставлять"
        case .alwaysClipboard: "Всегда в буфер"
        }
    }
}

enum TranscriptionQuality: String, Codable, CaseIterable, Identifiable {
    case faster
    case accurate

    var id: String { rawValue }

    var title: String {
        switch self {
        case .faster: "Быстрее"
        case .accurate: "Точнее"
        }
    }
}

struct AppSettings: Codable {
    var holdHotkey: Hotkey
    var toggleHotkey: Hotkey
    var outputMode: OutputMode
    var recognitionLanguage: String
    var transcriptionQuality: TranscriptionQuality
    var defaultActionID: String
    var customActions: [TextAction]
    var maxHistoryItems: Int
    var whisperCLIPath: String
    var fastModelPath: String
    var accurateModelPath: String
    var onboardingCompleted: Bool

    static var `default`: AppSettings {
        let appSupport = AppPaths.modelsDirectory.path
        return AppSettings(
            holdHotkey: .defaultHold,
            toggleHotkey: .defaultToggle,
            outputMode: .smart,
            recognitionLanguage: "auto",
            transcriptionQuality: .faster,
            defaultActionID: BuiltInActions.passthroughID,
            customActions: [],
            maxHistoryItems: 30,
            whisperCLIPath: "/opt/homebrew/bin/whisper-cli",
            fastModelPath: "\(appSupport)/ggml-base.bin",
            accurateModelPath: "\(appSupport)/ggml-medium.bin",
            onboardingCompleted: false
        )
    }

    var allActions: [TextAction] {
        var merged = BuiltInActions.all
        for action in customActions {
            if let builtInIndex = merged.firstIndex(where: { $0.id == action.id }) {
                merged[builtInIndex] = action
            } else {
                merged.append(action)
            }
        }
        return merged
    }

    func action(by id: String) -> TextAction? {
        allActions.first { $0.id == id }
    }

    var selectedAction: TextAction {
        action(by: defaultActionID) ?? BuiltInActions.all[0]
    }

    var modelPath: String {
        switch transcriptionQuality {
        case .faster: fastModelPath
        case .accurate: accurateModelPath
        }
    }
}
