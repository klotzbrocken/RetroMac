import AppKit
import CoreGraphics

/// Decides *when* a crash may happen, and — far more often — why it may not.
///
/// The list of reasons not to fire is longer than the arithmetic that decides to, and that is the
/// right proportion. A simulated blue screen is funny on your own desktop and unforgivable in the
/// middle of somebody's video call, so every way RetroMac can tell it is being watched by other
/// people is a reason to stay quiet.
final class CrashScheduler {

    static let shared = CrashScheduler()
    private init() {}

    // MARK: - Intensity

    enum Intensity: String, CaseIterable {
        case off, veryRare, rare, authentic, chaotic, manual

        var title: String {
            switch self {
            case .off:       return "Off"
            case .veryRare:  return "Very rare — about once a week"
            case .rare:      return "Rare — every few days"
            case .authentic: return "Authentic — now and then in a long session"
            // Every other level names its cadence; this one said only "for demos", so there was
            // nothing to notice when twenty-five minutes of nothing was in fact correct.
            case .chaotic:   return "Chaotic — about every 25 minutes, for demos"
            case .manual:    return "Manual only"
            }
        }
        /// Mean seconds between crashes. nil = never fires by itself.
        var meanInterval: TimeInterval? {
            switch self {
            case .off, .manual: return nil
            case .veryRare:  return 7 * 24 * 3600
            case .rare:      return 24 * 3600
            case .authentic: return 4 * 3600
            case .chaotic:   return 25 * 60
            }
        }
        var minimumGap: TimeInterval {
            switch self {
            case .off, .manual: return .infinity
            case .veryRare:  return 48 * 3600
            case .rare:      return 8 * 3600
            case .authentic: return 90 * 60
            case .chaotic:   return 8 * 60
            }
        }
        /// How long after launch nothing may fire.
        ///
        /// Ten minutes is right for the settings meant to surprise you during a working day. It
        /// is wrong for the demo setting, where the user has just chosen it, is sitting there,
        /// and the first ten minutes of silence read as a broken feature.
        var warmUp: TimeInterval {
            self == .chaotic ? 30 : 10 * 60
        }

        /// Whether this setting waits for the user to be at the machine but between actions.
        ///
        /// False for chaotic, and that is the whole point of the fix: the idle window is capped
        /// at two minutes, and a person waiting for a demo crash sits still, so their idle time
        /// passes two minutes and never comes back. The setting called "for demos" could not
        /// fire during a demo.
        var waitsForAQuietMoment: Bool { self != .chaotic }

        var dailyBudget: Int {
            switch self {
            case .off, .manual: return 0
            case .veryRare: return 1
            case .rare:     return 2
            case .authentic: return 5
            case .chaotic:  return .max
            }
        }
    }

    /// Why nothing is happening. The Crashes tab shows this, because "it never fires" with no
    /// explanation is indistinguishable from a broken feature.
    enum Hold: Equatable {
        case ready
        case notLicensed
        case intensityOff
        case partyMode
        case noTheme
        case noScenarios
        case streaming
        case recording
        case screenLocked
        case fullscreenApp
        case presenting(String)
        case alreadyRunning
        case settingsOpen
        case justLaunched
        case tooSoon
        case budgetSpent

        var explanation: String {
            switch self {
            case .ready:            return "Armed."
            case .notLicensed:      return "Retro Crashes is part of the licence."
            case .intensityOff:     return "Set to off — crashes only happen when you ask for one."
            case .partyMode:        return "Party mode never fires on its own."
            case .noTheme:          return "No theme is active."
            case .noScenarios:      return "This theme has no crashes yet."
            case .streaming:        return "Paused — RetroMac's virtual camera is running."
            case .recording:        return "Paused — RetroMac is recording shader video."
            case .screenLocked:     return "The screen is locked."
            case .fullscreenApp:    return "Paused — an app is running full screen."
            case .presenting(let app): return "Paused — \(app) is running."
            case .alreadyRunning:   return "A crash is already on screen."
            case .settingsOpen:     return "Paused while a RetroMac dialog is open."
            case .justLaunched:     return "Warming up — nothing fires in the first ten minutes."
            case .tooSoon:          return "Too soon after the last one."
            case .budgetSpent:      return "Today's crashes are used up."
            }
        }
    }

    /// Two lists, because the two cases are not the same question.
    ///
    /// A deck is only an audience while it is on screen, so these are checked FRONTMOST. Merely
    /// having Preview open is not a reason to disarm the feature for the rest of the day.
    private static let presentingApps: Set<String> = [
        "com.apple.iWork.Keynote", "com.microsoft.Powerpoint", "com.apple.Preview",
    ]

    /// These are checked while merely RUNNING, and that is the fix rather than a precaution:
    /// OBS streams from the background, and sharing a screen in Zoom, Teams or Webex puts the
    /// SHARED application in front, never the conferencing app. Testing only the frontmost app
    /// meant this list could not fire in the one situation it exists for.
    ///
    /// The cost is a false positive when one of them is open but idle. For a feature whose whole
    /// failure mode is a fake blue screen in front of somebody else's meeting, that is the right
    /// way round.
    private static let broadcastApps: Set<String> = [
        "com.obsproject.obs-studio", "us.zoom.xos", "com.microsoft.teams", "com.microsoft.teams2",
        "com.cisco.webexmeetingsapp", "com.google.Chrome.app.kjgfgldnnfoeklkmfkjfagphfepbbdan",
    ]

    private var timer: Timer?
    private var rng = CrashRNG(seed: UInt64(UInt32.random(in: 0...UInt32.max)))
    private let launchedAt = Date()

    var intensity: Intensity {
        Intensity(rawValue: AppSettings.shared.crashIntensity) ?? .off
    }
    var isPartyMode: Bool { AppSettings.shared.crashMode == "party" }

    // MARK: - Lifecycle (tied to the themed desktop, not to the app)

    func start() {
        guard timer == nil else { return }
        let t = Timer(timeInterval: 60, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    // MARK: - The decision

    private func tick() {
        let reason = hold()
        guard case .ready = reason else { return note("held: \(reason.explanation)") }
        let intensity = self.intensity
        guard let mean = intensity.meanInterval else { return note("held: no interval") }
        // One Bernoulli trial a minute rather than a countdown: a crash you cannot predict is
        // the only kind worth simulating.
        let p = 60.0 / mean
        guard Double.random(in: 0..<1, using: &rng) < p else { return note("armed, dice said no") }
        guard plausibleMoment(intensity) else { return note("armed, but not a plausible moment") }
        note("firing")
        fire(source: .random)
    }

    /// What the last tick decided, printed only when it changes.
    ///
    /// Without this there was no way to answer "it is set to chaotic and nothing happens": the
    /// settings tab shows `hold()`, which says "Armed", while the two steps that actually swallow
    /// the tick — the dice and the quiet-moment test — left no trace at all. Once a minute for a
    /// whole day would be 1,440 lines, so only changes are logged.
    private var lastTickNote = ""
    private func note(_ what: String) {
        guard what != lastTickNote else { return }
        lastTickNote = what
        print("[Crash] scheduler \(what)")
    }

    /// Everything that must be true before a crash may appear on its own.
    func hold(ignoringSchedule: Bool = false) -> Hold {
        guard LicenseManager.shared.isLicensed else { return .notLicensed }
        if !ignoringSchedule {
            guard intensity != .off else { return .intensityOff }
            guard intensity != .manual else { return .intensityOff }
            guard !isPartyMode else { return .partyMode }
        }
        guard AppSettings.shared.dockEnabled, let era = CrashEra.current() else { return .noTheme }
        let disabled = Set(AppSettings.shared.crashDisabledScenarios)
        guard CrashCatalogue.specs(for: era).contains(where: { !disabled.contains($0.id) }) else {
            return .noScenarios
        }
        guard !CrashDirector.shared.isStaging else { return .alreadyRunning }
        guard !SplashController.shared.isPresenting else { return .alreadyRunning }

        // The reasons that hold even when the user asked for it by hand.
        if VirtualCameraManager.shared.isRunning { return .streaming }
        if (NSApp.delegate as? AppDelegate)?.isRecordingShaderVideo == true { return .recording }
        if ScreensaverController.shared.active { return .screenLocked }
        if isScreenLocked() { return .screenLocked }
        if isSomeoneFullScreen() { return .fullscreenApp }
        if let app = NSWorkspace.shared.runningApplications.first(where: {
            guard let id = $0.bundleIdentifier else { return false }
            return Self.broadcastApps.contains(id)
        }) {
            return .presenting(app.localizedName ?? "A conferencing app")
        }
        if let front = NSWorkspace.shared.frontmostApplication,
           let id = front.bundleIdentifier, Self.presentingApps.contains(id) {
            return .presenting(front.localizedName ?? "That app")
        }
        if NSApp.modalWindow != nil { return .settingsOpen }

        if !ignoringSchedule {
            guard Date().timeIntervalSince(launchedAt) > intensity.warmUp else { return .justLaunched }
            let last = Date(timeIntervalSince1970: AppSettings.shared.crashLastFiredAt)
            guard AppSettings.shared.crashLastFiredAt == 0
                    || Date().timeIntervalSince(last) > intensity.minimumGap else { return .tooSoon }
            guard budgetLeft() > 0 else { return .budgetSpent }
        }
        return .ready
    }

    /// The user is at the machine, but between actions — not mid-sentence, not away. Idle time
    /// is the cheapest signal for that, and the screensaver already reads it the same way.
    ///
    /// The two bounds do different jobs, so they are not both negotiable. The lower one keeps a
    /// crash from landing in the middle of a keystroke and always applies. The upper one is what
    /// says "still there", and chaotic drops it: somebody demonstrating the feature stares at the
    /// screen without touching anything, sails past two minutes of idle, and from then on every
    /// tick fails this test forever.
    private func plausibleMoment(_ intensity: Intensity) -> Bool {
        let idle = CGEventSource.secondsSinceLastEventType(.combinedSessionState,
                                                           eventType: .init(rawValue: ~0)!)
        guard idle > 3 else { return false }
        return intensity.waitsForAQuietMoment ? idle < 120 : true
    }

    /// A full-screen app owns its own Mission Control Space, so a crash screen would either be
    /// invisible behind it or an ambush over it. The dock already answers this question for its
    /// own auto-hide, from its own window, with the caveats about newly created windows already
    /// handled — so ask it rather than guess from an arbitrary window of ours.
    private func isSomeoneFullScreen() -> Bool {
        DockController.shared.isFrontmostFullscreen
    }

    private func isScreenLocked() -> Bool {
        guard let info = CGSessionCopyCurrentDictionary() as? [String: Any] else { return false }
        return (info["CGSSessionScreenIsLocked"] as? Bool) == true
    }

    private func budgetLeft() -> Int {
        let settings = AppSettings.shared
        let today = Calendar.current.startOfDay(for: Date()).timeIntervalSince1970
        if settings.crashBudgetDay != today { return intensity.dailyBudget }
        return max(0, intensity.dailyBudget - settings.crashesToday)
    }

    private func noteFired() {
        let settings = AppSettings.shared
        let today = Calendar.current.startOfDay(for: Date()).timeIntervalSince1970
        if settings.crashBudgetDay != today {
            settings.crashBudgetDay = today
            settings.crashesToday = 0
        }
        settings.crashesToday += 1
        settings.crashLastFiredAt = Date().timeIntervalSince1970
    }

    // MARK: - Firing

    @discardableResult
    func fire(scenarioID: String? = nil, source: CrashDirector.Source = .manual,
              countdown: Int = 0) -> Bool {
        var scenario: CrashScenario?
        if let id = scenarioID, let spec = CrashCatalogue.spec(id: id) {
            scenario = spec.build(&rng)
        }
        let started = CrashDirector.shared.trigger(scenario, source: source, countdown: countdown)
        if started, source == .random { noteFired() }
        return started
    }
}
