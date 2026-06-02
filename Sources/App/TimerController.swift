import AppKit

/// Drives the two automation timers:
///  • a daily time window ("active from HH:MM to HH:MM")
///  • a one-shot countdown ("active for N minutes")
/// Each targets either the shader overlay or the full Retro Mode.
final class TimerController {
    static let shared = TimerController()

    private var windowTimer: Timer?
    private var windowActive = false          // did the window timer turn the target on?
    private var countdownItem: DispatchWorkItem?
    private(set) var countdownEndsAt: Date?

    private init() {}

    func start() {
        windowTimer?.invalidate()
        let t = Timer(timeInterval: 30, repeats: true) { [weak self] _ in self?.evaluateWindow() }
        RunLoop.main.add(t, forMode: .common)
        windowTimer = t
        evaluateWindow()
    }

    // MARK: - Daily window

    private func nowMinutes() -> Int {
        let c = Calendar.current.dateComponents([.hour, .minute], from: Date())
        return (c.hour ?? 0) * 60 + (c.minute ?? 0)
    }

    private func inWindow(_ now: Int, _ start: Int, _ end: Int) -> Bool {
        if start == end { return false }
        if start < end { return now >= start && now < end }
        return now >= start || now < end      // wraps past midnight
    }

    private func evaluateWindow() {
        let s = AppSettings.shared
        guard s.timerWindowEnabled else {
            if windowActive { setTarget(s.timerWindowTarget, false); windowActive = false }
            return
        }
        let shouldBeActive = inWindow(nowMinutes(), s.timerWindowStart, s.timerWindowEnd)
        if shouldBeActive && !windowActive {
            setTarget(s.timerWindowTarget, true); windowActive = true
        } else if !shouldBeActive && windowActive {
            setTarget(s.timerWindowTarget, false); windowActive = false
        }
    }

    // MARK: - Countdown

    func startCountdown(minutes: Int, target: String) {
        cancelCountdown()
        guard minutes > 0 else { return }
        setTarget(target, true)
        countdownEndsAt = Date().addingTimeInterval(TimeInterval(minutes * 60))
        let item = DispatchWorkItem { [weak self] in
            self?.setTarget(target, false)
            self?.countdownEndsAt = nil
            self?.countdownItem = nil
        }
        countdownItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + .seconds(minutes * 60), execute: item)
    }

    func cancelCountdown(deactivate: Bool = true) {
        countdownItem?.cancel()
        countdownItem = nil
        if deactivate, countdownEndsAt != nil {
            setTarget(AppSettings.shared.timerCountdownTarget, false)
        }
        countdownEndsAt = nil
    }

    var isCountingDown: Bool { countdownEndsAt != nil }

    // MARK: - Target dispatch

    private func setTarget(_ target: String, _ active: Bool) {
        DispatchQueue.main.async {
            (NSApp.delegate as? AppDelegate)?.applyTimerTarget(target, active: active)
        }
    }
}
