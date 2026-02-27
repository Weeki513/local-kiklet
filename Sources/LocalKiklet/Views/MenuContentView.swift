import SwiftUI

struct MenuContentView: View {
    @Environment(\.openWindow) private var openWindow
    @ObservedObject var model: AppViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Circle()
                    .fill(color(for: model.workflowState))
                    .frame(width: 10, height: 10)
                Text(model.workflowState.title)
                    .font(.headline)
            }

            Text(model.statusMessage)
                .font(.caption)
                .foregroundStyle(.secondary)

            Picker("Действие", selection: Binding(
                get: { model.settingsStore.settings.defaultActionID },
                set: { model.updateSelectedAction($0) }
            )) {
                ForEach(model.actions) { action in
                    Text(action.name).tag(action.id)
                }
            }

            Divider()

            Button(model.workflowState == .recording ? "Остановить запись" : "Начать запись") {
                model.startRecordingFromUI()
            }

            if model.workflowState == .transcribing || model.workflowState == .applyingAction {
                Button("Отменить") {
                    model.cancelCurrentWorkflow()
                }
            }

            Button("История") {
                openWindow(id: "history")
            }

            Button("Настройки") {
                openWindow(id: "settings")
            }

            if model.showOnboarding {
                Button("Онбординг") {
                    model.openOnboarding()
                    openWindow(id: "settings")
                }
            }

            if let lastError = model.lastErrorMessage {
                Divider()
                Text(lastError)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .lineLimit(3)
            }

            Divider()

            Button("Выход") {
                NSApplication.shared.terminate(nil)
            }
        }
        .padding(12)
        .frame(width: 320)
    }

    private func color(for state: WorkflowState) -> Color {
        switch state {
        case .idle: .green
        case .recording: .red
        case .transcribing, .applyingAction: .orange
        }
    }
}
