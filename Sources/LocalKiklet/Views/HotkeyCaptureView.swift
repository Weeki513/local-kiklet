import AppKit
import SwiftUI

struct HotkeyCaptureView: View {
    @Binding var hotkey: Hotkey
    let title: String

    @State private var isCapturing = false
    @State private var localMonitor: Any?
    @State private var globalMonitor: Any?
    @State private var previousModifiers: HotkeyModifiers = .none
    @State private var lastPressedModifierSet: HotkeyModifiers = .none
    @State private var lastPressedModifierKeyCode: Int?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            HStack {
                Text(hotkey.displayString)
                    .font(.system(.body, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)

                Button(isCapturing ? "Нажмите комбинацию..." : "Изменить") {
                    toggleCapture()
                }

                Button("Сброс") {
                    hotkey = Hotkey(keyCode: nil, modifiers: .none)
                }
                .disabled(isCapturing)
            }

            if isCapturing {
                Text("Для modifier-only нажмите и отпустите модификатор(ы)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .onDisappear {
            stopCapture()
        }
    }

    private func toggleCapture() {
        isCapturing ? stopCapture() : startCapture()
    }

    private func startCapture() {
        isCapturing = true
        previousModifiers = .none
        lastPressedModifierSet = .none
        lastPressedModifierKeyCode = nil

        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { event in
            if processEvent(event) {
                return nil
            }
            return event
        }

        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { event in
            DispatchQueue.main.async {
                _ = processEvent(event)
            }
        }
    }

    private func processEvent(_ event: NSEvent) -> Bool {
        guard isCapturing else { return false }

        let filteredFlags = event.modifierFlags.intersection([.command, .option, .shift, .control])
        let modifiers = HotkeyModifiers.from(filteredFlags)
        let keyCode = Int(event.keyCode)

        switch event.type {
        case .keyDown:
            if Hotkey.isModifierKeyCode(keyCode) {
                return true
            }
            hotkey = Hotkey(keyCode: keyCode, modifiers: modifiers)
            stopCapture()
            return true

        case .flagsChanged:
            handleModifierCapture(modifiers: modifiers, keyCode: keyCode)
            previousModifiers = modifiers
            return true

        default:
            return false
        }
    }

    private func handleModifierCapture(modifiers: HotkeyModifiers, keyCode: Int) {
        let previousCount = previousModifiers.count
        let currentCount = modifiers.count

        if currentCount > previousCount {
            lastPressedModifierSet = modifiers
            if Hotkey.isModifierKeyCode(keyCode) {
                lastPressedModifierKeyCode = keyCode
            }
        }

        if currentCount == 0,
           !lastPressedModifierSet.isEmpty {
            hotkey = Hotkey(keyCode: lastPressedModifierKeyCode, modifiers: lastPressedModifierSet)
            stopCapture()
        }
    }

    private func stopCapture() {
        isCapturing = false
        previousModifiers = .none
        lastPressedModifierSet = .none
        lastPressedModifierKeyCode = nil

        if let localMonitor {
            NSEvent.removeMonitor(localMonitor)
            self.localMonitor = nil
        }

        if let globalMonitor {
            NSEvent.removeMonitor(globalMonitor)
            self.globalMonitor = nil
        }
    }
}
