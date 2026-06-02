import AppKit
import Combine

/// DockFix ensures windows don't overlap the retro dock by adjusting
/// the active window's frame when it extends into the dock area.
final class DockFix {
    static let shared = DockFix()

    private var isActive = false
    private var observer: NSObjectProtocol?
    private var moveObserver: NSObjectProtocol?
    private var timer: Timer?
    private var settingsObserver: AnyCancellable?

    func start() {
        guard !isActive else { return }
        isActive = true

        // Watch for window activations
        observer = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            self?.adjustFrontmostWindow()
        }

        // Periodic check for window moves (every 2s, lightweight)
        timer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            self?.adjustFrontmostWindow()
        }

        // Initial adjustment
        adjustFrontmostWindow()
        print("[DockFix] Started")
    }

    func stop() {
        guard isActive else { return }
        isActive = false

        if let obs = observer {
            NSWorkspace.shared.notificationCenter.removeObserver(obs)
            observer = nil
        }
        timer?.invalidate()
        timer = nil
        print("[DockFix] Stopped")
    }

    private func adjustFrontmostWindow() {
        guard isActive,
              let dockFrame = DockController.shared.currentDockFrame(),
              let frontApp = NSWorkspace.shared.frontmostApplication,
              frontApp.bundleIdentifier != Bundle.main.bundleIdentifier else { return }

        let pid = frontApp.processIdentifier
        let appRef = AXUIElementCreateApplication(pid)

        var windowValue: AnyObject?
        guard AXUIElementCopyAttributeValue(appRef, kAXWindowsAttribute as CFString, &windowValue) == .success,
              let windows = windowValue as? [AXUIElement] else { return }

        // Only adjust the frontmost (first) window
        guard let window = windows.first else { return }

        var posValue: AnyObject?
        var sizeValue: AnyObject?
        guard AXUIElementCopyAttributeValue(window, kAXPositionAttribute as CFString, &posValue) == .success,
              AXUIElementCopyAttributeValue(window, kAXSizeAttribute as CFString, &sizeValue) == .success else { return }

        var pos = CGPoint.zero
        var size = CGSize.zero
        AXValueGetValue(posValue as! AXValue, .cgPoint, &pos)
        AXValueGetValue(sizeValue as! AXValue, .cgSize, &size)

        let windowRect = CGRect(origin: pos, size: size)

        // Convert dock frame to screen coordinates (CGWindow uses top-left origin)
        guard let screen = NSScreen.main else { return }
        let screenHeight = screen.frame.height
        let dockTop = screenHeight - dockFrame.minY  // convert from bottom-left to top-left
        let dockBottom = screenHeight - dockFrame.maxY
        let dockCGRect = CGRect(x: dockFrame.minX, y: dockBottom, width: dockFrame.width, height: dockFrame.height)

        let config = ThemeManager.shared.activeTheme?.config

        if config?.isVertical == true {
            // Vertical dock (left OR right) — dockCGRect already reflects the real
            // on-screen position, so pushing windows past its right edge is correct
            // for both sides.
            let dockRight = dockCGRect.maxX
            if windowRect.minX < dockRight {
                let newX = dockRight
                let newWidth = max(200, windowRect.maxX - dockRight)
                var newPos = CGPoint(x: newX, y: pos.y)
                var newSize = CGSize(width: newWidth, height: size.height)
                if let val = AXValueCreate(.cgPoint, &newPos) {
                    AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, val)
                }
                if newWidth != size.width, let val = AXValueCreate(.cgSize, &newSize) {
                    AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, val)
                }
            }
        } else {
            // Horizontal dock at the bottom
            let dockTopCG = dockCGRect.minY  // in CG coords (top-left origin), minY is top of dock
            let windowBottom = windowRect.maxY
            if windowBottom > dockTopCG {
                let newHeight = max(200, dockTopCG - windowRect.minY)
                var newSize = CGSize(width: size.width, height: newHeight)
                if let val = AXValueCreate(.cgSize, &newSize) {
                    AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, val)
                }
            }
        }
    }
}
