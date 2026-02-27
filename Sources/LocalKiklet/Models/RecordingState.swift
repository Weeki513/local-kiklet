import Foundation

enum WorkflowState: Equatable {
    case idle
    case recording
    case transcribing
    case applyingAction

    var title: String {
        switch self {
        case .idle: "Готово"
        case .recording: "Идёт запись"
        case .transcribing: "Транскрибирую"
        case .applyingAction: "Обрабатываю"
        }
    }
}
