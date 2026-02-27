import AppKit
import Foundation

@MainActor
final class CursorStatusHUD {
    private let panelSize = NSSize(width: 320, height: 44)
    private var panel: NSPanel?
    private var label: NSTextField?
    private var hideTask: Task<Void, Never>?
    private var trackingTimer: Timer?

    func showPersistent(text: String, color: NSColor = .labelColor) {
        hideTask?.cancel()
        hideTask = nil

        ensurePanel()
        update(text: text, color: color)
        positionNearCursor()
        panel?.orderFrontRegardless()
        startTrackingCursor()
    }

    func showTransient(text: String, color: NSColor = .labelColor, duration: TimeInterval = 1.3) {
        showPersistent(text: text, color: color)
        hideTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(duration))
            await MainActor.run {
                self?.hide()
            }
        }
    }

    func hide() {
        hideTask?.cancel()
        hideTask = nil
        stopTrackingCursor()
        panel?.orderOut(nil)
    }

    private func ensurePanel() {
        guard panel == nil else { return }

        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: panelSize),
            styleMask: [.nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.level = .statusBar
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.collectionBehavior = [.canJoinAllSpaces, .transient, .ignoresCycle]
        panel.ignoresMouseEvents = true

        let visual = NSVisualEffectView(frame: NSRect(origin: .zero, size: panelSize))
        visual.material = .hudWindow
        visual.state = .active
        visual.wantsLayer = true
        visual.layer?.cornerRadius = 10
        visual.layer?.masksToBounds = true

        let label = NSTextField(labelWithString: "")
        label.frame = visual.bounds.insetBy(dx: 14, dy: 10)
        label.autoresizingMask = [.width, .height]
        label.alignment = .center
        label.font = NSFont.systemFont(ofSize: 13, weight: .semibold)

        visual.addSubview(label)
        panel.contentView = visual

        self.label = label
        self.panel = panel
    }

    private func update(text: String, color: NSColor) {
        label?.stringValue = text
        label?.textColor = color
    }

    private func positionNearCursor() {
        guard let panel else { return }

        let mouse = NSEvent.mouseLocation
        var x = mouse.x + 16
        var y = mouse.y - panelSize.height - 16

        if let screen = NSScreen.screens.first(where: { NSMouseInRect(mouse, $0.frame, false) }) {
            let visible = screen.visibleFrame
            x = min(max(x, visible.minX + 8), visible.maxX - panelSize.width - 8)
            y = min(max(y, visible.minY + 8), visible.maxY - panelSize.height - 8)
        }

        panel.setFrameOrigin(NSPoint(x: x, y: y))
    }

    private func startTrackingCursor() {
        if trackingTimer != nil {
            return
        }

        let timer = Timer(timeInterval: 0.05, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.panel?.isVisible == true else { return }
                self.positionNearCursor()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        trackingTimer = timer
    }

    private func stopTrackingCursor() {
        trackingTimer?.invalidate()
        trackingTimer = nil
    }
}
