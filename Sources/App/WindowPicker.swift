import AppKit
import ScreenCaptureKit

final class WindowPicker {
    private var overlayWindow: NSWindow?
    private var trackingArea: NSTrackingArea?
    private var highlightView: NSView?
    private var completion: ((SCWindow?) -> Void)?
    private var scWindows: [SCWindow] = []
    private var eventMonitor: Any?

    func pick(completion: @escaping (SCWindow?) -> Void) {
        self.completion = completion

        Task {
            do {
                self.scWindows = try await ScreenCaptureManager.listWindows()
                await MainActor.run { self.startPicking() }
            } catch {
                print("[WindowPicker] Failed to list windows: \(error)")
                completion(nil)
            }
        }
    }

    @MainActor
    private func startPicking() {
        guard let screen = NSScreen.main else {
            completion?(nil)
            return
        }

        let overlay = NSWindow(
            contentRect: screen.frame,
            styleMask: .borderless,
            backing: .buffered,
            defer: false,
            screen: screen
        )
        overlay.level = NSWindow.Level(rawValue: 100)
        overlay.isOpaque = false
        overlay.backgroundColor = NSColor.black.withAlphaComponent(0.3)
        overlay.ignoresMouseEvents = false
        overlay.hasShadow = false

        let contentView = PickerContentView(frame: screen.frame)
        contentView.onWindowSelected = { [weak self] point in
            self?.handleClick(at: point)
        }
        contentView.onCancel = { [weak self] in
            self?.cancel()
        }
        overlay.contentView = contentView
        overlay.makeKeyAndOrderFront(nil)
        self.overlayWindow = overlay

        // Change cursor
        NSCursor.crosshair.push()

        // ESC to cancel
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 { // ESC
                self?.cancel()
                return nil
            }
            return event
        }

        print("[WindowPicker] Active — click a window or ESC to cancel")
    }

    private func handleClick(at screenPoint: NSPoint) {
        // Convert from NSWindow coordinates to CGWindow coordinates
        guard let screen = NSScreen.main else {
            cancel()
            return
        }
        let cgPoint = CGPoint(
            x: screenPoint.x,
            y: screen.frame.height - screenPoint.y
        )

        // Find the window under the click point using CGWindowListCopyWindowInfo
        let windowList = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []

        let ownPID = ProcessInfo.processInfo.processIdentifier

        let excludedNames: Set<String> = ["Dock", "Window Manager", "Control Center", "Notification Center"]

        for info in windowList {
            guard let pid = info[kCGWindowOwnerPID as String] as? Int32,
                  pid != ownPID,
                  let bounds = info[kCGWindowBounds as String] as? [String: CGFloat],
                  let x = bounds["X"], let y = bounds["Y"],
                  let w = bounds["Width"], let h = bounds["Height"],
                  w > 50 && h > 50 else { continue }

            let ownerName = info[kCGWindowOwnerName as String] as? String ?? ""
            if excludedNames.contains(ownerName) { continue }

            let rect = CGRect(x: x, y: y, width: w, height: h)
            if rect.contains(cgPoint) {
                let windowID = info[kCGWindowNumber as String] as? CGWindowID ?? 0
                // Find matching SCWindow
                if let scWindow = scWindows.first(where: { $0.windowID == windowID }) {
                    let appName = scWindow.owningApplication?.applicationName ?? "Unknown"
                    print("[WindowPicker] Selected: \(appName) — \(scWindow.title ?? "Untitled")")
                    cleanup()
                    completion?(scWindow)
                    return
                }
            }
        }

        print("[WindowPicker] No matching window at click point")
        cleanup()
        completion?(nil)
    }

    private func cancel() {
        print("[WindowPicker] Cancelled")
        cleanup()
        completion?(nil)
    }

    private func cleanup() {
        NSCursor.pop()
        overlayWindow?.orderOut(nil)
        overlayWindow = nil
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
            eventMonitor = nil
        }
    }
}

private class PickerContentView: NSView {
    var onWindowSelected: ((NSPoint) -> Void)?
    var onCancel: (() -> Void)?

    override var acceptsFirstResponder: Bool { true }

    override func mouseDown(with event: NSEvent) {
        onWindowSelected?(NSEvent.mouseLocation)
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.black.withAlphaComponent(0.3).setFill()
        dirtyRect.fill()

        // Draw hint text
        let text = "Click on a window to apply the shader effect\nPress ESC to cancel"
        let attrs: [NSAttributedString.Key: Any] = [
            .foregroundColor: NSColor.white,
            .font: NSFont.systemFont(ofSize: 24, weight: .medium),
        ]
        let size = (text as NSString).size(withAttributes: attrs)
        let point = NSPoint(
            x: (bounds.width - size.width) / 2,
            y: bounds.height / 2 - size.height / 2
        )
        (text as NSString).draw(at: point, withAttributes: attrs)
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 {
            onCancel?()
        }
    }
}
