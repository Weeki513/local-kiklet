import ApplicationServices
import Carbon
import Foundation

enum HotkeyMonitorError: LocalizedError {
    case tapCreationFailed
    case carbonHandlerFailed(OSStatus)

    var errorDescription: String? {
        switch self {
        case .tapCreationFailed:
            "Не удалось включить обработку modifier-only горячих клавиш. Проверьте Input Monitoring."
        case .carbonHandlerFailed(let status):
            "Не удалось зарегистрировать глобальные горячие клавиши (OSStatus: \(status))."
        }
    }
}

final class HotkeyMonitor {
    var onHoldStart: (() -> Void)?
    var onHoldStop: (() -> Void)?
    var onTogglePressed: (() -> Void)?

    private let logger: AppLogger
    private var holdHotkey: Hotkey
    private var toggleHotkey: Hotkey

    private var isStarted = false
    private var isHoldActive = false

    private var previousModifiers: HotkeyModifiers = .none
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    private var hotKeyEventHandler: EventHandlerRef?
    private var holdHotKeyRef: EventHotKeyRef?
    private var toggleHotKeyRef: EventHotKeyRef?

    private let hotKeySignature: UInt32 = 0x4C4B4C4B // "LKLK"

    private enum HotKeyID: UInt32 {
        case hold = 1
        case toggle = 2
    }

    init(holdHotkey: Hotkey, toggleHotkey: Hotkey, logger: AppLogger = .shared) {
        self.holdHotkey = holdHotkey
        self.toggleHotkey = toggleHotkey
        self.logger = logger
    }

    func update(holdHotkey: Hotkey, toggleHotkey: Hotkey) {
        if self.holdHotkey == holdHotkey && self.toggleHotkey == toggleHotkey {
            return
        }

        self.holdHotkey = holdHotkey
        self.toggleHotkey = toggleHotkey

        guard isStarted else { return }

        do {
            try registerCarbonHotkeys()
            try configureModifierOnlyTap()
        } catch {
            logger.error("Hotkey reconfiguration failed: \(error.localizedDescription)")
        }
    }

    func start() throws {
        guard !isStarted else { return }

        try registerCarbonHotkeys()
        var tapError: Error?
        do {
            try configureModifierOnlyTap()
        } catch {
            tapError = error
            logger.warn("Modifier-only hotkeys unavailable: \(error.localizedDescription)")
        }

        isStarted = true
        logger.info("Hotkey monitor started")

        if requiresModifierOnlyTap,
           holdHotKeyRef == nil,
           toggleHotKeyRef == nil,
           let tapError {
            throw tapError
        }
    }

    func stop() {
        unregisterCarbonHotkeys()
        stopModifierTap()

        isStarted = false
        isHoldActive = false
        previousModifiers = .none
        logger.info("Hotkey monitor stopped")
    }

    private func registerCarbonHotkeys() throws {
        try installCarbonHandlerIfNeeded()
        unregisterCarbonHotkeysOnly()

        if let holdKeyCode = holdHotkey.keyCode,
           !holdHotkey.isModifierOnly {
            holdHotKeyRef = registerCarbonHotkey(
                keyCode: holdKeyCode,
                modifiers: holdHotkey.modifiers,
                id: .hold
            )
        }

        if let toggleKeyCode = toggleHotkey.keyCode,
           !toggleHotkey.isModifierOnly {
            toggleHotKeyRef = registerCarbonHotkey(
                keyCode: toggleKeyCode,
                modifiers: toggleHotkey.modifiers,
                id: .toggle
            )
        }
    }

    private func installCarbonHandlerIfNeeded() throws {
        if hotKeyEventHandler != nil {
            return
        }

        var eventTypes = [
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed)),
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyReleased))
        ]

        let callback: EventHandlerUPP = { _, eventRef, userData in
            guard let userData else { return noErr }
            let monitor = Unmanaged<HotkeyMonitor>.fromOpaque(userData).takeUnretainedValue()
            return monitor.handleCarbonEvent(eventRef)
        }

        let status = InstallEventHandler(
            GetApplicationEventTarget(),
            callback,
            eventTypes.count,
            &eventTypes,
            UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque()),
            &hotKeyEventHandler
        )

        guard status == noErr else {
            throw HotkeyMonitorError.carbonHandlerFailed(status)
        }
    }

    private func registerCarbonHotkey(keyCode: Int, modifiers: HotkeyModifiers, id: HotKeyID) -> EventHotKeyRef? {
        var hotKeyRef: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(signature: hotKeySignature, id: id.rawValue)

        let status = RegisterEventHotKey(
            UInt32(keyCode),
            carbonModifiers(from: modifiers),
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )

        if status != noErr {
            logger.warn("RegisterEventHotKey failed for id=\(id.rawValue), status=\(status)")
            return nil
        }

        return hotKeyRef
    }

    private func unregisterCarbonHotkeys() {
        unregisterCarbonHotkeysOnly()
        if let handler = hotKeyEventHandler {
            RemoveEventHandler(handler)
        }
        hotKeyEventHandler = nil
    }

    private func unregisterCarbonHotkeysOnly() {
        if let holdHotKeyRef {
            UnregisterEventHotKey(holdHotKeyRef)
            self.holdHotKeyRef = nil
        }

        if let toggleHotKeyRef {
            UnregisterEventHotKey(toggleHotKeyRef)
            self.toggleHotKeyRef = nil
        }
    }

    private func handleCarbonEvent(_ eventRef: EventRef?) -> OSStatus {
        guard let eventRef else { return noErr }

        var hotKeyID = EventHotKeyID()
        let status = GetEventParameter(
            eventRef,
            EventParamName(kEventParamDirectObject),
            EventParamType(typeEventHotKeyID),
            nil,
            MemoryLayout<EventHotKeyID>.size,
            nil,
            &hotKeyID
        )

        guard status == noErr, hotKeyID.signature == hotKeySignature else {
            return noErr
        }

        let kind = GetEventKind(eventRef)

        switch hotKeyID.id {
        case HotKeyID.hold.rawValue:
            if kind == UInt32(kEventHotKeyPressed), !isHoldActive {
                isHoldActive = true
                onHoldStart?()
            } else if kind == UInt32(kEventHotKeyReleased), isHoldActive {
                isHoldActive = false
                onHoldStop?()
            }

        case HotKeyID.toggle.rawValue:
            if kind == UInt32(kEventHotKeyPressed) {
                onTogglePressed?()
            }

        default:
            break
        }

        return noErr
    }

    private func configureModifierOnlyTap() throws {
        guard requiresModifierOnlyTap else {
            stopModifierTap()
            return
        }

        if eventTap != nil {
            return
        }

        let mask = (1 << CGEventType.flagsChanged.rawValue)
        let callback: CGEventTapCallBack = { _, type, event, refcon in
            guard let refcon else { return Unmanaged.passUnretained(event) }
            let monitor = Unmanaged<HotkeyMonitor>.fromOpaque(refcon).takeUnretainedValue()
            return monitor.handleModifierTapEvent(event: event, type: type)
        }

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: CGEventMask(mask),
            callback: callback,
            userInfo: UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        ) else {
            throw HotkeyMonitorError.tapCreationFailed
        }

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        eventTap = tap
        runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
    }

    private func stopModifierTap() {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }

        eventTap = nil
        runLoopSource = nil
        previousModifiers = .none
    }

    private func handleModifierTapEvent(event: CGEvent, type: CGEventType) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap = eventTap {
                CGEvent.tapEnable(tap: tap, enable: true)
            }
            return Unmanaged.passUnretained(event)
        }

        guard type == .flagsChanged else {
            return Unmanaged.passUnretained(event)
        }

        let keyCode = Int(event.getIntegerValueField(.keyboardEventKeycode))
        let modifiers = HotkeyModifiers.from(event.flags)
        handleModifierOnlyHotkeys(modifiers: modifiers, changedKeyCode: keyCode)
        previousModifiers = modifiers
        return Unmanaged.passUnretained(event)
    }

    private var requiresModifierOnlyTap: Bool {
        holdHotkey.isModifierOnly || toggleHotkey.isModifierOnly
    }

    private func handleModifierOnlyHotkeys(modifiers: HotkeyModifiers, changedKeyCode: Int) {
        if toggleHotkey.isModifierOnly,
           matchesModifierOnlyHotkey(toggleHotkey, modifiers: modifiers, changedKeyCode: changedKeyCode),
           !wasMatchingModifierOnlyHotkey(toggleHotkey, modifiers: previousModifiers) {
            onTogglePressed?()
        }

        if holdHotkey.isModifierOnly {
            if !isHoldActive,
               matchesModifierOnlyHotkey(holdHotkey, modifiers: modifiers, changedKeyCode: changedKeyCode),
               !wasMatchingModifierOnlyHotkey(holdHotkey, modifiers: previousModifiers) {
                isHoldActive = true
                onHoldStart?()
            } else if isHoldActive,
                      !wasMatchingModifierOnlyHotkey(holdHotkey, modifiers: modifiers) {
                isHoldActive = false
                onHoldStop?()
            }
        }
    }

    private func matchesModifierOnlyHotkey(_ hotkey: Hotkey, modifiers: HotkeyModifiers, changedKeyCode: Int) -> Bool {
        guard wasMatchingModifierOnlyHotkey(hotkey, modifiers: modifiers) else { return false }
        guard let requiredKeyCode = hotkey.keyCode, Hotkey.isModifierKeyCode(requiredKeyCode) else {
            return true
        }
        return requiredKeyCode == changedKeyCode
    }

    private func wasMatchingModifierOnlyHotkey(_ hotkey: Hotkey, modifiers: HotkeyModifiers) -> Bool {
        hotkey.isModifierOnly && modifiers == hotkey.modifiers
    }

    private func carbonModifiers(from modifiers: HotkeyModifiers) -> UInt32 {
        var result: UInt32 = 0
        if modifiers.command { result |= UInt32(cmdKey) }
        if modifiers.option { result |= UInt32(optionKey) }
        if modifiers.shift { result |= UInt32(shiftKey) }
        if modifiers.control { result |= UInt32(controlKey) }
        return result
    }

}
