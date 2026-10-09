import AppKit
import Carbon.HIToolbox

/// Mac OS 9 (authentic) has no Dock on screen, so a window minimised the macOS way shrinks
/// into a corner where nothing is. Under that theme a window leaves the Mac OS 9 way instead:
/// its picture, Platinum bar and all, zooms away to the top of the desktop and is gone.
///
/// The real minimise still has to happen, and the WindowServer plays it on the window itself
/// — the window shrinks in place towards the hidden Dock; the Dock draws nothing of its own.
/// So a still of everything under the window goes over it first, ordered just above it, and
/// hides the shrinking window until the app reports the minimise done. Windows above the
/// leaving one stay above the still, and the desktop under it stands for a third of a second.
///
/// ⌘M is taken over while the theme is on, so a minimise from the keyboard goes the same way.
final class MinimizeZoom {

    static let shared = MinimizeZoom()
    private init() {}

    /// Under the theme without a dock, Mac OS 9 (authentic), and under a Windows taskbar, where a
    /// window goes into its button.
    static var wanted: Bool {
        guard let config = ThemeManager.shared.activeTheme?.config else { return false }
        return config.isControlStripModules || config.hasTaskButtons
    }

    static let duration: TimeInterval = 0.4
    /// Windows' caption flight to the taskbar: quick, as fast as a maximise feels.
    static let captionDuration: TimeInterval = 0.2

    private var cover: NSPanel?
    private var zoom: NSPanel?
    private var coverGeneration = 0

    // MARK: Zoom away

    /// Put the still over the window and start the zoom. `windowBounds` is the window in
    /// Quartz coordinates (top-left origin), `bar` its bar panel, still on screen. Returns
    /// false when nothing could be photographed; the minimise then runs as macOS plays it.
    /// `target`: the taskbar button to fly into (screen coordinates); nil zooms to the top.
    func begin(wid: CGWindowID, windowBounds: CGRect, bar: NSPanel, barView: NSView, patch: NSPanel?, target button: NSRect? = nil) -> Bool {
        end()
        guard let screen = NSScreen.screens.first(where: { $0.frame.intersects(bar.frame) }) ?? NSScreen.main else { return false }
        let primaryTop = NSScreen.screens.first?.frame.maxY ?? screen.frame.maxY
        let windowFrame = NSRect(x: windowBounds.minX, y: primaryTop - windowBounds.maxY, width: windowBounds.width, height: windowBounds.height)
        let screenQuartz = CGRect(x: screen.frame.minX, y: primaryTop - screen.frame.maxY, width: screen.frame.width, height: screen.frame.height)

        // The still: everything under the window, at the display's own resolution.
        guard let belowCG = CGWindowListCreateImage(screenQuartz, .optionOnScreenBelowWindow, wid, [.bestResolution]),
              let shotCG = CGWindowListCreateImage(.null, .optionIncludingWindow, wid, [.boundsIgnoreFraming, .bestResolution]),
              shotCG.width > 1, shotCG.height > 1 else { return false }

        // The picture that zooms: the window with its bar on top, as they stood. Into a
        // taskbar button only the bar goes, as Windows animated the caption alone.
        let union = button == nil ? windowFrame.union(bar.frame) : bar.frame
        let picture = NSImage(size: union.size)
        picture.lockFocus()
        if button == nil { NSImage(cgImage: shotCG, size: windowFrame.size).draw(in: NSRect(origin: NSPoint(x: windowFrame.minX - union.minX, y: windowFrame.minY - union.minY), size: windowFrame.size)) }
        if let rep = barView.bitmapImageRepForCachingDisplay(in: barView.bounds) {
            barView.cacheDisplay(in: barView.bounds, to: rep)
            let barImage = NSImage(size: barView.bounds.size); barImage.addRepresentation(rep)
            barImage.draw(in: NSRect(origin: NSPoint(x: bar.frame.minX - union.minX, y: bar.frame.minY - union.minY), size: bar.frame.size))
        }
        // The patch over the window's own traffic lights goes on the picture too, or the
        // lights would show up on it the moment it starts to move.
        if let patch, let patchView = patch.contentView, let rep = patchView.bitmapImageRepForCachingDisplay(in: patchView.bounds) {
            patchView.cacheDisplay(in: patchView.bounds, to: rep)
            let patchImage = NSImage(size: patchView.bounds.size); patchImage.addRepresentation(rep)
            patchImage.draw(in: NSRect(origin: NSPoint(x: patch.frame.minX - union.minX, y: patch.frame.minY - union.minY), size: patch.frame.size))
        }
        picture.unlockFocus()

        let coverPanel = Self.panel(frame: screen.frame)
        let coverView = NSImageView(frame: NSRect(origin: .zero, size: screen.frame.size))
        coverView.imageScaling = .scaleAxesIndependently
        coverView.image = NSImage(cgImage: belowCG, size: screen.frame.size)
        coverPanel.contentView = coverView
        coverPanel.order(.above, relativeTo: Int(wid))
        cover = coverPanel

        let zoomPanel = Self.panel(frame: screen.frame)
        let host = NSView(frame: NSRect(origin: .zero, size: screen.frame.size))
        host.wantsLayer = true
        let layer = CALayer()
        layer.contents = picture.cgImage(forProposedRect: nil, context: nil, hints: nil)
        layer.contentsGravity = .resize
        layer.frame = NSRect(x: union.minX - screen.frame.minX, y: union.minY - screen.frame.minY, width: union.width, height: union.height)
        host.layer?.addSublayer(layer)
        zoomPanel.contentView = host
        zoomPanel.order(.above, relativeTo: coverPanel.windowNumber)
        zoom = zoomPanel
        // Both on screen now, not at the end of this run-loop turn: the bar goes right after
        // this, and a frame with the bar gone and the still not yet up shows the window's own
        // title bar.
        coverPanel.display(); zoomPanel.display()
        CATransaction.flush()

        // Away to the top of the desktop, under the menu bar, shrinking to nothing — solid all
        // the way, as the zoom rectangles of the day were, not a ghost. Under Windows, into the
        // window's taskbar button, shrinking to its size.
        let target = button.map { CGPoint(x: $0.midX - screen.frame.minX, y: $0.midY - screen.frame.minY) }
            ?? CGPoint(x: screen.frame.midX - screen.frame.minX, y: screen.visibleFrame.maxY - screen.frame.minY - 12)
        let endScale = button.map { CATransform3DMakeScale($0.width / union.width, $0.height / union.height, 1) }
            ?? CATransform3DMakeScale(0.02, 0.02, 1)
        CATransaction.begin()
        CATransaction.setAnimationDuration(button == nil ? Self.duration : Self.captionDuration)
        CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(name: button == nil ? .easeIn : .easeInEaseOut))
        CATransaction.setCompletionBlock { [weak self] in self?.dropZoom(zoomPanel) }
        let move = CABasicAnimation(keyPath: "position"); move.fromValue = layer.position; move.toValue = target
        let shrink = CABasicAnimation(keyPath: "transform"); shrink.fromValue = CATransform3DIdentity; shrink.toValue = endScale
        for a in [move, shrink] { a.isRemovedOnCompletion = false; a.fillMode = .forwards; layer.add(a, forKey: a.keyPath) }
        CATransaction.commit()

        // Never longer than the minimise could take: a window that ignores the request must
        // not leave the desktop frozen under a still.
        coverGeneration += 1
        let generation = coverGeneration
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            guard let self, self.coverGeneration == generation else { return }
            self.end()
        }
        return true
    }

    /// The minimise is done (the app answered): the still goes.
    func end() {
        coverGeneration += 1
        if let cover { cover.orderOut(nil); self.cover = nil }
    }

    private func dropZoom(_ panel: NSPanel) {
        panel.orderOut(nil)
        if zoom === panel { zoom = nil }
    }

    private static func panel(frame: NSRect) -> NSPanel {
        let p = NSPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = false
        p.ignoresMouseEvents = true
        p.setAccessibilityElement(false)   // drawing only: no "new window" for VoiceOver
        p.hidesOnDeactivate = false
        p.isReleasedWhenClosed = false
        p.animationBehavior = .none
        p.collectionBehavior = [.ignoresCycle, .fullScreenAuxiliary, .stationary]
        return p
    }

    // MARK: ⌘M

    private var hotKey: EventHotKeyRef?
    private var handler: EventHandlerRef?
    var onCommandM: (() -> Void)?

    /// Take ⌘M while the theme is on (and let it go when it is not).
    func setHotKey(_ on: Bool) {
        if on, hotKey == nil {
            if handler == nil {
                var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
                InstallEventHandler(GetApplicationEventTarget(), { _, event, _ -> OSStatus in
                    var id = EventHotKeyID()
                    GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil,
                                      MemoryLayout<EventHotKeyID>.size, nil, &id)
                    guard id.signature == MinimizeZoom.signature else { return OSStatus(eventNotHandledErr) }
                    DispatchQueue.main.async { MinimizeZoom.shared.onCommandM?() }
                    return noErr
                }, 1, &spec, nil, &handler)
            }
            var ref: EventHotKeyRef?
            let id = EventHotKeyID(signature: Self.signature, id: 1)
            if RegisterEventHotKey(UInt32(kVK_ANSI_M), UInt32(cmdKey), id, GetApplicationEventTarget(), 0, &ref) == noErr { hotKey = ref }
        } else if !on, let hotKey {
            UnregisterEventHotKey(hotKey)
            self.hotKey = nil
        }
    }
    private static let signature = OSType(0x524D5A4D)   // "RMZM"
}
