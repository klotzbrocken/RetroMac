import IOKit.ps
import ScreenSaver

/// Base class for every saver in the collection. It handles what all of them need from the
/// host, so a subclass overrides `setAnimating(_:)`, `frameRateDidChange()` and, if it cares,
/// `sizeDidSettle()`:
///
/// - Since macOS Sonoma, `stopAnimation()` isn't reliably called and the legacyScreenSaver host
///   keeps old instances alive (and drawing). The "will stop" notification is the dependable
///   signal, so this stops animating on it and quits the lingering host.
/// - Size changes are debounced, so a live window resize in the harness reports once at the end.
/// - On battery or in Low Power Mode the frame rate drops to `reducedFrameRate`, and goes back up
///   as soon as the Mac is plugged in again.
class RetroScreenSaverView: ScreenSaverView {
    /// The most any saver draws at on battery or in Low Power Mode.
    static let reducedFrameRate = 30
    /// Pretend to be on battery, to try out the reduced frame rate (the harness's `--battery`).
    static var simulatesBattery = false

    /// The frame rate the saver wants when plugged in.
    var fullFrameRate = 60 {
        didSet { updateFrameRate() }
    }
    /// The frame rate to draw at right now.
    private(set) var frameRate = 60

    private var willStopObserver: NSObjectProtocol?
    private var lowPowerModeObserver: NSObjectProtocol?
    private var powerSourceObserver: CFRunLoopSource?

    override init?(frame: NSRect, isPreview: Bool) {
        super.init(frame: frame, isPreview: isPreview)
        willStopObserver = DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name("com.apple.screensaver.willstop"), object: nil, queue: .main
        ) { [weak self] _ in
            self?.screenSaverWillStop()
        }

        lowPowerModeObserver = NotificationCenter.default.addObserver(
            forName: .NSProcessInfoPowerStateDidChange, object: nil, queue: .main
        ) { [weak self] _ in
            self?.updateFrameRate()
        }
        // Called whenever the Mac switches between battery and power adapter.
        let context = Unmanaged.passUnretained(self).toOpaque()
        if let source = IOPSNotificationCreateRunLoopSource({ context in
            guard let context else { return }
            Unmanaged<RetroScreenSaverView>.fromOpaque(context).takeUnretainedValue().updateFrameRate()
        }, context)?.takeRetainedValue() {
            CFRunLoopAddSource(CFRunLoopGetMain(), source, .defaultMode)
            powerSourceObserver = source
        }
        updateFrameRate()
    }

    required init?(coder: NSCoder) {
        nil
    }

    deinit {
        if let willStopObserver {
            DistributedNotificationCenter.default().removeObserver(willStopObserver)
        }
        if let lowPowerModeObserver {
            NotificationCenter.default.removeObserver(lowPowerModeObserver)
        }
        if let powerSourceObserver {
            CFRunLoopSourceInvalidate(powerSourceObserver)
        }
    }

    /// Starts or stops drawing. Called from start/stopAnimation() and when the screen saver stops.
    func setAnimating(_ isAnimating: Bool) {}

    /// Called when `frameRate` changes; apply it to whatever drives the drawing.
    func frameRateDidChange() {}

    /// Called once the view's size has stopped changing.
    func sizeDidSettle() {}

    override func startAnimation() {
        super.startAnimation()
        setAnimating(true)
    }

    override func stopAnimation() {
        super.stopAnimation()
        setAnimating(false)
    }

    override func resizeSubviews(withOldSize oldSize: NSSize) {
        super.resizeSubviews(withOldSize: oldSize)
        guard bounds.size != oldSize else { return }
        NSObject.cancelPreviousPerformRequests(withTarget: self, selector: #selector(notifySizeDidSettle), object: nil)
        perform(#selector(notifySizeDidSettle), with: nil, afterDelay: 0.3)
    }

    @objc private func notifySizeDidSettle() {
        sizeDidSettle()
    }

    private func updateFrameRate() {
        let rate = Self.isSavingPower ? min(fullFrameRate, Self.reducedFrameRate) : fullFrameRate
        guard rate != frameRate else { return }
        frameRate = rate
        frameRateDidChange()
    }

    private static var isSavingPower: Bool {
        if simulatesBattery || ProcessInfo.processInfo.isLowPowerModeEnabled {
            return true
        }
        // If the power source can't be read, assume a power adapter.
        guard let source = IOPSGetProvidingPowerSourceType(nil)?.takeUnretainedValue() else { return false }
        return source as String == kIOPMBatteryPowerKey
    }

    private func screenSaverWillStop() {
        setAnimating(false)
        // Quit the lingering host process so stale instances don't pile up across activations;
        // macOS launches a fresh one next time. Never do this for the System Settings preview
        // or when hosted by the test harness.
        if !isPreview, ProcessInfo.processInfo.processName.hasPrefix("legacyScreenSaver") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                exit(0)
            }
        }
    }
}
