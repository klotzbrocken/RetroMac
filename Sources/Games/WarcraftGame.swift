import AppKit
import ScreenCaptureKit

/// Warcraft: Orcs & Humans and Warcraft II on the bundled Stratagus engine (GPL-2), launched
/// as a separate process — never linked, so its GPL-2 stays clear of RetroMac's GPL-3.
///
/// A Stratagus data folder is two halves that must come from different places:
///   • the GPL game logic (scripts/campaigns/maps/contrib/shaders) — shipped in our bundle
///   • the game media (graphics/sounds/music/videos/…) — the user's own copy of the game
/// `prepareRuntime` merges them under Application Support: the logic is copied, the media
/// is symlinked (it runs to hundreds of megabytes).
///
/// The user's own scripts are deliberately NOT used. Some distributions patch them for
/// engine functions a stock build doesn't have — the PS Vita release, for instance, calls
/// `SetControllerSpeed`, which aborts the Lua stage on this engine.
enum WarcraftGame {

    enum Title: String {
        case warcraft1, warcraft2

        /// Lua namespace the game's scripts use for preferences (`wc1.preferences.…`).
        var namespace: String { self == .warcraft2 ? "wc2" : "wc1" }
        /// Folder of GPL game logic inside our bundle.
        var baseFolder: String { self == .warcraft2 ? "wc2-base" : "wc1-base" }
        /// Config the extractor writes to record WHAT was extracted (expansion present?
        /// music format?). It describes the user's media, so it must come from their data.
        var configFile: String { self == .warcraft2 ? "wc2-config.lua" : "wc1-config.lua" }
        var displayName: String { self == .warcraft2 ? "Warcraft II" : "Warcraft: Orcs & Humans" }

        /// Media sub-folders the user's data must provide.
        var mediaFolders: [String] {
            self == .warcraft2
                ? ["graphics", "sounds", "music", "videos", "wc2", "wargus.exp.data"]
                : ["graphics", "sounds", "music", "videos"]
        }
    }

    // MARK: - Bundle layout

    private static var gamesDir: URL? {
        Bundle.main.resourceURL?.appendingPathComponent("Games/Warcraft")
    }
    static var engineURL: URL? { gamesDir?.appendingPathComponent("stratagus") }
    static var wartoolURL: URL? { gamesDir?.appendingPathComponent("wartool") }

    /// True when the engine and this title's game logic are present in the bundle.
    static func isEngineAvailable(_ title: Title) -> Bool {
        guard let engine = engineURL, let base = gamesDir?.appendingPathComponent(title.baseFolder) else { return false }
        let fm = FileManager.default
        return fm.isExecutableFile(atPath: engine.path)
            && fm.fileExists(atPath: base.appendingPathComponent("scripts").path)
    }

    // MARK: - User data

    static func dataFolder(_ title: Title) -> String {
        title == .warcraft2 ? AppSettings.shared.warcraft2DataFolder : AppSettings.shared.warcraft1DataFolder
    }

    /// True when `dir` holds already-extracted game data: the media folders plus the
    /// extractor's config. (A raw game installation does not — that needs `wartool` first.)
    static func hasExtractedData(at dir: URL, _ title: Title) -> Bool {
        let fm = FileManager.default
        guard fm.fileExists(atPath: dir.appendingPathComponent("scripts/\(title.configFile)").path) else { return false }
        // "graphics" alone is enough to tell extracted data from an installer folder.
        return fm.fileExists(atPath: dir.appendingPathComponent("graphics").path)
    }

    static func hasExtractedData(_ title: Title) -> Bool {
        let path = dataFolder(title)
        guard !path.isEmpty else { return false }
        return hasExtractedData(at: URL(fileURLWithPath: path), title)
    }

    /// True when `dir` is a raw game installation — i.e. it holds the archives the extractor
    /// reads (maindat.war and friends), rather than data someone already extracted.
    static func looksLikeInstallation(at dir: URL, _ title: Title) -> Bool {
        // Only Warcraft II for now: extracting Warcraft I needs war1tool, which this build
        // does not produce (war1gus is vendored for its game logic only).
        guard title == .warcraft2, canExtract(title) else { return false }
        guard let items = try? FileManager.default.contentsOfDirectory(atPath: dir.path) else { return false }
        return items.contains { $0.lowercased() == "maindat.war" }
    }

    /// Whether RetroMac can extract this title itself (i.e. the matching tool is bundled).
    static func canExtract(_ title: Title) -> Bool {
        guard title == .warcraft2, let tool = wartoolURL else { return false }
        return FileManager.default.isExecutableFile(atPath: tool.path)
    }

    /// Where RetroMac puts data it extracted itself.
    private static func extractedDataDir(_ title: Title) -> URL {
        supportDir.appendingPathComponent("\(title.namespace)-extracted")
    }

    /// Why an extraction failed, in words we can show the user directly.
    struct ExtractionFailure: Error { let message: String }

    /// Run the bundled extractor over a raw game installation, into our own support folder.
    /// Off the main thread; `completion` lands back on the main queue.
    static func extract(_ title: Title, from source: URL,
                        completion: @escaping (Result<URL, ExtractionFailure>) -> Void) {
        guard let tool = wartoolURL, FileManager.default.isExecutableFile(atPath: tool.path) else {
            completion(.failure(ExtractionFailure(message: "The extraction tool is not bundled with this build.")))
            return
        }
        let dest = extractedDataDir(title)
        DispatchQueue.global(qos: .userInitiated).async {
            let fm = FileManager.default
            try? fm.removeItem(at: dest)
            try? fm.createDirectory(at: dest, withIntermediateDirectories: true)

            let p = Process()
            p.executableURL = tool
            p.arguments = [source.path, dest.path]
            let pipe = Pipe()
            p.standardOutput = pipe; p.standardError = pipe
            do { try p.run() } catch {
                DispatchQueue.main.async {
                    completion(.failure(ExtractionFailure(message: error.localizedDescription)))
                }
                return
            }
            let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            p.waitUntilExit()

            DispatchQueue.main.async {
                if p.terminationStatus == 0, hasExtractedData(at: dest, title) {
                    completion(.success(dest))
                } else {
                    let tail = output.split(separator: "\n").suffix(2).joined(separator: " — ")
                    completion(.failure(ExtractionFailure(message: tail.isEmpty
                        ? "The extractor exited with status \(p.terminationStatus)."
                        : String(tail))))
                }
            }
        }
    }

    static func isPlayable(_ title: Title) -> Bool {
        isEngineAvailable(title) && hasExtractedData(title)
    }

    // MARK: - Runtime

    private static var supportDir: URL {
        URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent("Library/Application Support/RetroMac/Warcraft")
    }
    private static func runtimeDataDir(_ title: Title) -> URL {
        supportDir.appendingPathComponent("\(title.namespace)-data")
    }
    private static func userStateDir(_ title: Title) -> URL {
        supportDir.appendingPathComponent("\(title.namespace)-user")
    }

    /// Merge the bundled GPL logic with the user's media into a runnable data folder.
    @discardableResult
    static func prepareRuntime(_ title: Title) -> URL? {
        let fm = FileManager.default
        guard let base = gamesDir?.appendingPathComponent(title.baseFolder),
              fm.fileExists(atPath: base.path) else { return nil }
        let userData = URL(fileURLWithPath: dataFolder(title))
        guard !dataFolder(title).isEmpty, fm.fileExists(atPath: userData.path) else { return nil }

        let run = runtimeDataDir(title)
        try? fm.removeItem(at: run)
        try? fm.createDirectory(at: run, withIntermediateDirectories: true)

        // GPL half — copied from the bundle.
        for d in ["scripts", "campaigns", "maps", "contrib", "shaders"] {
            let src = base.appendingPathComponent(d)
            guard fm.fileExists(atPath: src.path) else { continue }
            try? fm.copyItem(at: src, to: run.appendingPathComponent(d))
        }
        // Media half — symlinked from the user's data (hundreds of MB; never copy).
        for d in title.mediaFolders {
            let src = userData.appendingPathComponent(d)
            guard fm.fileExists(atPath: src.path) else { continue }
            try? fm.createSymbolicLink(at: run.appendingPathComponent(d), withDestinationURL: src)
        }
        // The extractor's config belongs to the user's media, not to our scripts.
        let cfgSrc = userData.appendingPathComponent("scripts/\(title.configFile)")
        if fm.fileExists(atPath: cfgSrc.path) {
            let dst = run.appendingPathComponent("scripts/\(title.configFile)")
            try? fm.removeItem(at: dst)
            try? fm.copyItem(at: cfgSrc, to: dst)
        }
        return run
    }

    // MARK: - Presentation

    /// Patch one `<ns>.preferences.<key>` line in the engine's own preferences.lua. The engine
    /// loads that file at startup and rewrites it on exit, so this is re-applied every launch
    /// and never fights the user's in-game choices for other settings.
    private static func setPreference(_ title: Title, _ key: String, _ value: String) {
        let fm = FileManager.default
        let ns = title.namespace
        let prefsDir = userStateDir(title).appendingPathComponent(ns)
        try? fm.createDirectory(at: prefsDir, withIntermediateDirectories: true)
        let prefs = prefsDir.appendingPathComponent("preferences.lua")

        var lines: [String]
        if let existing = try? String(contentsOf: prefs, encoding: .utf8), !existing.isEmpty {
            lines = existing.components(separatedBy: "\n")
                .filter { !$0.contains("\(ns).preferences.\(key)") }
        } else {
            lines = ["if (\(ns) == nil) then \(ns) = {} end",
                     "if (\(ns).preferences == nil) then \(ns).preferences = {} end"]
        }
        lines.append("\(ns).preferences.\(key) = \(value)")
        try? lines.joined(separator: "\n").write(to: prefs, atomically: true, encoding: .utf8)
    }

    /// Windowed by default — the engine draws a RetroMac title bar itself when we hand it a
    /// theme (see the chrome patch in vendor/patches), so a window is what we want. The user's
    /// own fullscreen choice is left alone: the engine persists VideoFullScreen and can toggle
    /// it in-game, and its fullscreen is a borderless desktop window rather than an exclusive
    /// mode, so the CRT overlay keeps working either way.
    private static func applyDisplayPreference(_ title: Title) {
        // Only seed a default on the very first run; never override the user afterwards.
        let prefs = userStateDir(title)
            .appendingPathComponent(title.namespace)
            .appendingPathComponent("preferences.lua")
        guard !FileManager.default.fileExists(atPath: prefs.path) else { return }
        setPreference(title, "VideoFullScreen", "false")
    }

    // MARK: - CRT

    private static var overlayPollTimer: Timer?

    /// Lay RetroMac's CRT shader over the game window, the same ScreenCaptureKit path the ROM
    /// emulators use (see ROMLauncher).
    ///
    /// Stratagus has its own GLSL shaders and even a built-in "CRT", but it compiles the whole
    /// shader layer out on Apple (`#ifndef __APPLE__`). That guard is not cosmetic: force the
    /// code back in and the shaders do compile, yet the render path — libretro-style shaders
    /// driven through OpenGL immediate mode — draws a black screen after the intro. So the
    /// overlay it is.
    ///
    /// The game is a bare binary rather than an app bundle, so its window is matched by the
    /// PID we launched rather than a bundle identifier.
    private static func startShaderOverlay(pid: pid_t) {
        guard AppSettings.shared.gamesCRTEnabled,
              let appDel = NSApp.delegate as? AppDelegate else { return }
        let preset = appDel.launcherCurrentPreset
        guard !preset.isEmpty else { return }

        var attempts = 0
        overlayPollTimer?.invalidate()
        overlayPollTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { timer in
            attempts += 1
            if attempts > 20 {   // 10s — the engine loads its data before showing a window
                timer.invalidate(); overlayPollTimer = nil
                print("[Warcraft] Timed out waiting for the game window — no CRT overlay")
                return
            }
            Task {
                guard let content = try? await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true),
                      let scWindow = content.windows.first(where: {
                          $0.owningApplication?.processID == pid
                              && $0.frame.width > 100 && $0.frame.height > 100
                      })
                else { return }

                await MainActor.run {
                    timer.invalidate(); overlayPollTimer = nil
                    appDel.saveOverlayState()
                    if appDel.isActive { appDel.disableAll() }
                    // Let the game paint a frame before capturing it.
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        appDel.startWindowOverlay(window: scWindow, presetID: preset)
                        print("[Warcraft] CRT overlay attached (preset: \(preset))")
                        // The overlay must not hold focus — the game needs the keyboard.
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                            NSRunningApplication(processIdentifier: pid)?.activate()
                        }
                    }
                }
            }
        }
    }

    // MARK: - Launch

    static func launch(_ title: Title) {
        guard let engine = engineURL, FileManager.default.isExecutableFile(atPath: engine.path) else {
            alert("\(title.displayName) engine missing",
                  "The Stratagus engine was not bundled with this build.")
            return
        }
        guard hasExtractedData(title) else {
            alert("No \(title.displayName) data configured",
                  "Choose your extracted \(title.displayName) data folder in Settings → Games.")
            return
        }
        guard let run = prepareRuntime(title) else {
            alert("Could not prepare \(title.displayName)",
                  "The game data folder could not be combined with the bundled game logic.")
            return
        }
        let user = userStateDir(title)
        try? FileManager.default.createDirectory(at: user, withIntermediateDirectories: true)
        applyDisplayPreference(title)

        let p = Process()
        p.executableURL = engine
        p.arguments = ["-d", run.path, "-u", user.path]
        // RETROMAC_THEME makes the engine draw our window chrome instead of the OS title bar
        // (see the chrome patch in vendor/patches); HOME keeps its state inside our support
        // folder rather than the user's real home, the way peonpad's own run script isolates
        // a profile.
        var env = RetroFrameTheme.gameEnv()
        env["HOME"] = user.path
        p.environment = env
        do {
            try p.run()
            print("[Warcraft] Launched \(title.displayName) (data: \(run.path))")
            startShaderOverlay(pid: p.processIdentifier)
        } catch {
            print("[Warcraft] Launch failed: \(error)")
            alert("Could not launch \(title.displayName)", "\(error.localizedDescription)")
        }
    }

    private static func alert(_ title: String, _ info: String) {
        NSSound.beep()
        let a = NSAlert()
        a.messageText = title
        a.informativeText = info
        a.alertStyle = .warning
        NSApp.activate(ignoringOtherApps: true)
        a.runModal()
    }
}
