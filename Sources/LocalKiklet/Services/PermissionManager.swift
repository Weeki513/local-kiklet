import AppKit
import AVFoundation
import ApplicationServices
import Foundation

enum PermissionKind: String, CaseIterable, Identifiable {
    case microphone
    case accessibility
    case inputMonitoring

    var id: String { rawValue }

    var title: String {
        switch self {
        case .microphone: "Микрофон"
        case .accessibility: "Accessibility"
        case .inputMonitoring: "Input Monitoring"
        }
    }

    var subtitle: String {
        switch self {
        case .microphone:
            "Для записи речи"
        case .accessibility:
            "Для вставки текста в сторонние приложения"
        case .inputMonitoring:
            "Для глобальных горячих клавиш"
        }
    }

    var settingsURL: URL? {
        switch self {
        case .microphone:
            URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")
        case .accessibility:
            URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
        case .inputMonitoring:
            URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent")
        }
    }
}

@MainActor
final class PermissionManager: ObservableObject {
    @Published private(set) var states: [PermissionKind: Bool] = [:]

    init() {
        refreshStatuses()
    }

    var allGranted: Bool {
        PermissionKind.allCases.allSatisfy { states[$0] == true }
    }

    func status(for kind: PermissionKind) -> Bool {
        states[kind] == true
    }

    func refreshStatuses() {
        states[.microphone] = microphoneGranted
        states[.accessibility] = accessibilityGranted
        states[.inputMonitoring] = inputMonitoringGranted
    }

    func request(_ kind: PermissionKind) async {
        switch kind {
        case .microphone:
            _ = await AVCaptureDevice.requestAccess(for: .audio)
        case .accessibility:
            let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
            _ = AXIsProcessTrustedWithOptions(options)
        case .inputMonitoring:
            _ = requestInputMonitoring(showSettingsIfNeeded: true)
        }
        refreshStatuses()
    }

    @discardableResult
    func requestInputMonitoring(showSettingsIfNeeded: Bool) -> Bool {
        let granted = CGRequestListenEventAccess()
        refreshStatuses()
        if !inputMonitoringGranted,
           showSettingsIfNeeded,
           let url = PermissionKind.inputMonitoring.settingsURL {
            NSWorkspace.shared.open(url)
        }
        return granted
    }

    func requestInputMonitoringIfNeeded() async {
        guard !inputMonitoringGranted else {
            return
        }
        _ = requestInputMonitoring(showSettingsIfNeeded: false)
    }

    func openSettings(for kind: PermissionKind) {
        guard let url = kind.settingsURL else { return }
        NSWorkspace.shared.open(url)
    }

    var microphoneGranted: Bool {
        AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
    }

    var accessibilityGranted: Bool {
        AXIsProcessTrusted()
    }

    var inputMonitoringGranted: Bool {
        CGPreflightListenEventAccess()
    }
}
