import AppKit
import SwiftUI

struct SettingsRootView: View {
    @ObservedObject var model: AppViewModel

    var body: some View {
        Group {
            if model.showOnboarding {
                OnboardingView(model: model)
            } else {
                SettingsView(model: model)
            }
        }
        .onAppear {
            model.checkPermissions()
            model.refreshLaunchAtLoginState()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            model.checkPermissions()
            model.refreshLaunchAtLoginState()
        }
    }
}
