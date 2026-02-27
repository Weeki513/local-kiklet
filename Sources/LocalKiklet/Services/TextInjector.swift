import AppKit
import ApplicationServices
import Foundation

enum DeliveryResult {
    case inserted(String)
    case copied
}

final class TextInjector {
    private let clipboard: ClipboardService
    private let logger: AppLogger

    init(clipboard: ClipboardService = ClipboardService(), logger: AppLogger = .shared) {
        self.clipboard = clipboard
        self.logger = logger
    }

    func deliver(_ text: String, mode: OutputMode) -> DeliveryResult {
        switch mode {
        case .alwaysClipboard:
            clipboard.copy(text)
            return .copied
        case .alwaysInput:
            return deliverToInputOrClipboard(text)
        case .smart:
            if hasFocusedEditableElement() {
                return deliverToInputOrClipboard(text)
            }

            if accessibilityGranted {
                logger.info("Editable target not detected by AX, trying paste fallback")
                let fallback = deliverToInputOrClipboard(text)
                if case .inserted = fallback {
                    return fallback
                }
            }

            clipboard.copy(text)
            logger.info("No editable target, copied to clipboard")
            return .copied
        }
    }

    private func deliverToInputOrClipboard(_ text: String) -> DeliveryResult {
        clipboard.copy(text)
        if triggerPasteShortcut() {
            let appName = NSWorkspace.shared.frontmostApplication?.localizedName ?? "приложение"
            return .inserted(appName)
        }
        return .copied
    }

    private func triggerPasteShortcut() -> Bool {
        guard accessibilityGranted else {
            logger.warn("Accessibility is not granted, cannot post Cmd+V")
            return false
        }

        let source = CGEventSource(stateID: .combinedSessionState)
        guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: false) else {
            logger.warn("Unable to build paste events")
            return false
        }

        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand
        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)
        logger.info("Paste shortcut posted")
        return true
    }

    private func hasFocusedEditableElement() -> Bool {
        let systemWide = AXUIElementCreateSystemWide()
        var focused: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(systemWide, kAXFocusedUIElementAttribute as CFString, &focused)
        guard result == .success,
              let focused,
              CFGetTypeID(focused) == AXUIElementGetTypeID() else {
            return false
        }

        let element = unsafeDowncast(focused, to: AXUIElement.self)

        var roleValue: CFTypeRef?
        let roleResult = AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &roleValue)
        if roleResult == .success, let role = roleValue as? String {
            let knownEditableRoles: Set<String> = [
                kAXTextFieldRole as String,
                kAXTextAreaRole as String,
                "AXSearchField",
                kAXComboBoxRole as String,
                "AXWebArea",
                "AXDocument",
                "AXTextView"
            ]
            if knownEditableRoles.contains(role) {
                return true
            }
        }

        var editableValue: CFTypeRef?
        let editableAttr = "AXEditable" as CFString
        let editableResult = AXUIElementCopyAttributeValue(element, editableAttr, &editableValue)
        if editableResult == .success, let editable = editableValue as? Bool, editable {
            return true
        }

        var canSetValue = DarwinBoolean(false)
        let settableResult = AXUIElementIsAttributeSettable(element, kAXValueAttribute as CFString, &canSetValue)
        return settableResult == .success && canSetValue.boolValue
    }

    private var accessibilityGranted: Bool {
        AXIsProcessTrusted()
    }
}
