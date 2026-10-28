import AppKit
import ApplicationServices

/// The work area of the real systems: a window never settled under the taskbar or the dock.
/// When an app window comes to rest overlapping the retro bar, it is moved clear of it, or made
/// smaller when it does not fit. Watched through each app's Accessibility notifications (moved,
/// resized, created) and looked at 150 ms after its last change, never while a mouse button is
/// down. It never fights an app or the user: a frame it moved a window from is left alone if the
/// window comes back to it, and no window is moved more than twice in ten seconds. Full-screen
/// windows, sheets, panels and RetroMac's own are never touched. Every Accessibility call runs on
/// the title bars' Accessibility queue, never on the main thread (PERF-05).
///
/// After macOS 7 Ultimate SP1's WorkAreaKeeper (github.com/kaganisildak/macOS-7-Ultimate-SP1, GPL-3.0).
final class WorkAreaKeeper {
    static let shared = WorkAreaKeeper()

    private struct Key: Hashable {
        let element: AXUIElement
        static func == (a: Key, b: Key) -> Bool { CFEqual(a.element, b.element) }
        func hash(into h: inout Hasher) { h.combine(CFHash(element)) }
    }

    private struct Memory {
        var looked: CGRect?
        var movedFrom: [CGRect] = []
        var moves: [Double] = []
    }

    private var observers: [pid_t: AXObserver] = [:]
    private var pending: [Key: DispatchWorkItem] = [:]
    private var memory: [Key: Memory] = [:]
    private var tokens: [NSObjectProtocol] = []
    private(set) var isActive = false

    func start() {
        guard !isActive else { return }
        isActive = true
        let ws = NSWorkspace.shared
        for app in ws.runningApplications where Self.eligible(app) { observe(app.processIdentifier, attempt: 0, now: true) }
        tokens.append(ws.notificationCenter.addObserver(forName: NSWorkspace.didLaunchApplicationNotification,
                                                        object: nil, queue: .main) { [weak self] note in
            guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                  Self.eligible(app) else { return }
            self?.observe(app.processIdentifier, attempt: 0)
        })
        tokens.append(ws.notificationCenter.addObserver(forName: NSWorkspace.didTerminateApplicationNotification,
                                                        object: nil, queue: .main) { [weak self] note in
            guard let pid = (note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.processIdentifier,
                  let obs = self?.observers.removeValue(forKey: pid) else { return }
            CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(obs), .defaultMode)
        })
        print("[WorkArea] Started")
    }

    func stop() {
        guard isActive else { return }
        isActive = false
        tokens.forEach(NSWorkspace.shared.notificationCenter.removeObserver)
        tokens = []
        for obs in observers.values { CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(obs), .defaultMode) }
        observers = [:]
        pending.values.forEach { $0.cancel() }
        pending = [:]
        Self.queue.async { self.memory = [:] }
        print("[WorkArea] Stopped")
    }

    private static func eligible(_ app: NSRunningApplication) -> Bool {
        app.activationPolicy == .regular && app.processIdentifier != getpid() && !app.isTerminated
    }

    // MARK: - Observation

    private static let retryDelays: [Double] = [0.5, 2, 5]

    /// A just-launched app often refuses an observer until it has finished launching.
    private func observe(_ pid: pid_t, attempt: Int, now: Bool = false) {
        DispatchQueue.main.asyncAfter(deadline: .now() + (now ? 0 : Self.retryDelays[attempt])) { [weak self] in
            guard let self, self.isActive, self.observers[pid] == nil else { return }
            Self.queue.async {
                let obs = self.attach(pid)
                let windows = obs == nil ? [] : Self.windows(of: pid)
                DispatchQueue.main.async {
                    guard let obs else {
                        if attempt + 1 < Self.retryDelays.count { self.observe(pid, attempt: attempt + 1) }
                        return
                    }
                    guard self.isActive, self.observers[pid] == nil else {
                        return CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(obs), .defaultMode)
                    }
                    self.observers[pid] = obs
                    windows.forEach { self.schedule($0, pid: pid) }
                }
            }
        }
    }

    private static let queue = TitleBarOverlayController.axQueue

    /// On the queue: the observer, its source already on the main run loop.
    private func attach(_ pid: pid_t) -> AXObserver? {
        var made: AXObserver?
        let callback: AXObserverCallback = { _, element, _, refcon in
            guard let refcon else { return }
            var pid: pid_t = 0
            AXUIElementGetPid(element, &pid)
            Unmanaged<WorkAreaKeeper>.fromOpaque(refcon).takeUnretainedValue().schedule(element, pid: pid)
        }
        guard AXObserverCreate(pid, callback, &made) == .success, let obs = made else { return nil }
        let app = AXUIElementCreateApplication(pid), me = Unmanaged.passUnretained(self).toOpaque()
        var any = false
        for n in [kAXWindowCreatedNotification, kAXWindowMovedNotification, kAXWindowResizedNotification] {
            if AXObserverAddNotification(obs, app, n as CFString, me) == .success { any = true }
        }
        guard any else { return nil }
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(obs), .defaultMode)
        return obs
    }

    private static func windows(of pid: pid_t) -> [AXUIElement] {
        var value: AnyObject?
        guard AXUIElementCopyAttributeValue(AXUIElementCreateApplication(pid), kAXWindowsAttribute as CFString, &value) == .success
        else { return [] }
        return value as? [AXUIElement] ?? []
    }

    /// No Accessibility call here: a change only re-arms the window's settle timer.
    private func schedule(_ window: AXUIElement, pid: pid_t) {
        guard isActive else { return }
        let key = Key(element: window)
        pending[key]?.cancel()
        let item = DispatchWorkItem { [weak self] in
            guard let self, self.isActive else { return }
            self.pending[key] = nil
            // A drag or a resize in progress: look again once the button is up.
            if NSEvent.pressedMouseButtons != 0 { return self.schedule(window, pid: pid) }
            guard let bar = DockController.shared.currentDockFrame(), let geometry = Self.geometry(barAppKit: bar) else { return }
            Self.queue.async { self.settle(window, key: key, geometry: geometry) }
        }
        pending[key] = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: item)
    }

    // MARK: - Settling

    /// On the queue, which alone touches `memory`.
    private func settle(_ window: AXUIElement, key: Key, geometry: (visible: CGRect, bar: CGRect)) {
        guard Self.string(window, kAXSubroleAttribute) == (kAXStandardWindowSubrole as String),
              Self.bool(window, "AXFullScreen") != true, Self.bool(window, kAXMinimizedAttribute) != true,
              let frame = Self.frame(of: window) else { return }
        var mem = memory[key] ?? Memory()
        defer { memory[key] = mem }
        // Each frame is looked at once; one it was moved from is the user's or the app's choice.
        guard frame != mem.looked, !mem.movedFrom.contains(frame) else { return }
        mem.looked = frame
        guard let target = WorkArea.adjusted(frame: frame, visible: geometry.visible, bar: geometry.bar) else { return }
        let now = ProcessInfo.processInfo.systemUptime
        mem.moves = mem.moves.filter { now - $0 < 10 }
        guard mem.moves.count < 2 else { return }
        if target.size != frame.size { Self.set(window, size: target.size) }
        Self.set(window, origin: target.origin)
        let result = Self.frame(of: window) ?? target
        mem.movedFrom.append(frame)
        mem.moves.append(now)
        mem.looked = result
    }

    /// The bar's screen's visible frame and the bar, in Accessibility coordinates (top-left origin).
    private static func geometry(barAppKit: NSRect) -> (visible: CGRect, bar: CGRect)? {
        guard let primary = NSScreen.screens.first else { return nil }
        let screen = NSScreen.screens.first { $0.frame.intersects(barAppKit) } ?? primary
        let h = primary.frame.height
        func ax(_ r: NSRect) -> CGRect { CGRect(x: r.minX, y: h - r.maxY, width: r.width, height: r.height) }
        return (ax(screen.visibleFrame), ax(barAppKit))
    }

    // MARK: - Accessibility

    static func frame(of window: AXUIElement) -> CGRect? {
        var p: AnyObject?, s: AnyObject?
        guard AXUIElementCopyAttributeValue(window, kAXPositionAttribute as CFString, &p) == .success,
              AXUIElementCopyAttributeValue(window, kAXSizeAttribute as CFString, &s) == .success else { return nil }
        var origin = CGPoint.zero, size = CGSize.zero
        AXValueGetValue(p as! AXValue, .cgPoint, &origin)
        AXValueGetValue(s as! AXValue, .cgSize, &size)
        return CGRect(origin: origin, size: size)
    }

    static func set(_ window: AXUIElement, origin: CGPoint) {
        var o = origin
        if let v = AXValueCreate(.cgPoint, &o) { AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, v) }
    }

    static func set(_ window: AXUIElement, size: CGSize) {
        var s = size
        if let v = AXValueCreate(.cgSize, &s) { AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, v) }
    }

    private static func string(_ e: AXUIElement, _ attr: String) -> String? {
        var v: AnyObject?
        return AXUIElementCopyAttributeValue(e, attr as CFString, &v) == .success ? v as? String : nil
    }

    private static func bool(_ e: AXUIElement, _ attr: String) -> Bool? {
        var v: AnyObject?
        return AXUIElementCopyAttributeValue(e, attr as CFString, &v) == .success ? (v as? Bool) : nil
    }
}

/// The geometry, in Accessibility coordinates (y down).
enum WorkArea {
    /// The visible frame minus the band of the bar, on the side the bar sits on.
    static func usable(visible: CGRect, bar: CGRect) -> CGRect {
        var r = visible
        if bar.width >= bar.height {
            if bar.midY > visible.midY { r.size.height = max(0, bar.minY - r.minY) }
            else { let top = max(r.minY, bar.maxY); r.size.height -= top - r.minY; r.origin.y = top }
        } else {
            if bar.midX > visible.midX { r.size.width = max(0, bar.minX - r.minX) }
            else { let left = max(r.minX, bar.maxX); r.size.width -= left - r.minX; r.origin.x = left }
        }
        return r
    }

    /// Where a window overlapping the bar should go: moved just clear of it, or shrunk to the work
    /// area where it is too big to fit. Nil when it does not overlap the bar.
    static func adjusted(frame: CGRect, visible: CGRect, bar: CGRect) -> CGRect? {
        guard frame.intersects(bar), visible.intersects(frame) else { return nil }
        let area = usable(visible: visible, bar: bar)
        guard area.width >= 200, area.height >= 150 else { return nil }
        var f = frame
        f.size.width = min(f.width, area.width)
        f.size.height = min(f.height, area.height)
        f.origin.x = min(max(f.minX, area.minX), area.maxX - f.width)
        f.origin.y = min(max(f.minY, area.minY), area.maxY - f.height)
        return f == frame ? nil : f
    }
}
