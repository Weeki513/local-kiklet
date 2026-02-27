import SwiftUI

@main
struct LocalKikletApp: App {
    @StateObject private var model = AppViewModel()

    var body: some Scene {
        MenuBarExtra("Local Kiklet", systemImage: iconName(for: model.workflowState)) {
            MenuContentView(model: model)
        }
        .menuBarExtraStyle(.window)

        WindowGroup(id: "settings") {
            SettingsRootView(model: model)
        }
        .defaultSize(width: 820, height: 700)

        WindowGroup(id: "history") {
            HistoryView(model: model)
        }
        .defaultSize(width: 820, height: 560)
    }

    private func iconName(for state: WorkflowState) -> String {
        switch state {
        case .idle:
            "waveform"
        case .recording:
            "record.circle"
        case .transcribing, .applyingAction:
            "hourglass"
        }
    }
}
