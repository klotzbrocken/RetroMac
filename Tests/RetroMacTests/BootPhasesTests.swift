import XCTest
@testable import RetroMac

/// Boot Phases: the move from the two boot-screen switches, what a theme actually plays, the
/// firmware declared by the themes, and the BIOS settings.
final class BootPhasesTests: XCTestCase {

    private func fresh(_ name: String = #function) -> UserDefaults {
        let suite = "BootPhasesTests.\(name)"
        UserDefaults().removePersistentDomain(forName: suite)
        return UserDefaults(suiteName: suite)!
    }

    /// A new install starts on the desktop; an existing one keeps what it had.
    func testMigration() {
        let new = fresh("new")
        AppSettings.migrateBootPhases(new)
        XCTAssertEqual(new.string(forKey: "bootPhaseMode"), "desktop")

        let on = fresh("on")
        on.set("com.retromac.microsoft.windows98", forKey: "dockTheme")
        on.set(["a": false, "b": true], forKey: "themeBootscreenEnabled")
        AppSettings.migrateBootPhases(on)
        XCTAssertEqual(on.string(forKey: "bootPhaseMode"), "os", "boot screens were on by default")
        XCTAssertEqual(on.dictionary(forKey: "themeBootPhase") as? [String: String], ["a": "desktop"],
                       "a theme switched off stays off; one switched on needs no override")

        let off = fresh("off")
        off.set(true, forKey: "setupWizardComplete")
        off.set(false, forKey: "showSplashScreen")
        off.set(["b": true], forKey: "themeBootscreenEnabled")
        AppSettings.migrateBootPhases(off)
        XCTAssertEqual(off.string(forKey: "bootPhaseMode"), "desktop")
        XCTAssertNil(off.dictionary(forKey: "themeBootPhase"), "globally off meant off everywhere")

        off.set("full", forKey: "bootPhaseMode")
        AppSettings.migrateBootPhases(off)
        XCTAssertEqual(off.string(forKey: "bootPhaseMode"), "full", "runs once")
    }

    /// The choice cut down to what the theme has, and VoiceOver/Reduce Motion skip it.
    func testEffectiveMode() {
        XCTAssertEqual(BootPhaseMode.effective(.full, hasOS: true, hasFirmware: true), .full)
        XCTAssertEqual(BootPhaseMode.effective(.full, hasOS: true, hasFirmware: false), .os)
        XCTAssertEqual(BootPhaseMode.effective(.full, hasOS: false, hasFirmware: false), .desktop)
        XCTAssertEqual(BootPhaseMode.effective(.full, hasOS: false, hasFirmware: true), .full)
        XCTAssertEqual(BootPhaseMode.effective(.os, hasOS: false, hasFirmware: true), .desktop)
        XCTAssertEqual(BootPhaseMode.effective(.os, hasOS: true, hasFirmware: true), .os)
        XCTAssertEqual(BootPhaseMode.effective(.full, hasOS: true, hasFirmware: true, voiceOver: true), .desktop)
        XCTAssertEqual(BootPhaseMode.effective(.os, hasOS: true, hasFirmware: true, reduceMotion: true), .desktop)
    }

    /// Every Windows theme names its firmware, nothing else does, and the page knows each one.
    func testThemesDeclareKnownFirmware() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let page = try String(contentsOf: root.appendingPathComponent("Resources/Widgets/Boot/Boot.html"), encoding: .utf8)
        let dir = root.appendingPathComponent("Resources/Themes")
        var seen = 0
        for bundle in try FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)
            where bundle.pathExtension == "retromactheme" {
            let config = try JSONDecoder().decode(DockThemeConfig.self, from: Data(contentsOf: bundle.appendingPathComponent("theme.json")))
            let windows = bundle.lastPathComponent.hasPrefix("Windows")
            if let fw = config.boot?.firmware {
                XCTAssertTrue(windows, "\(bundle.lastPathComponent): firmware only on PC themes")
                XCTAssertTrue(["ami92", "award451", "award600"].contains(fw), fw)
                XCTAssertTrue(page.contains("\(fw): {"), "Boot.html has no \(fw)")
                seen += 1
            } else {
                XCTAssertFalse(windows, "\(bundle.lastPathComponent) has no firmware")
            }
        }
        XCTAssertGreaterThanOrEqual(seen, 7)
    }

    /// Windows NT Workstation 4.0: the desktop of a fresh install in its order, 95's Start menu
    /// with NT's groups, the Award BIOS and NT's own text-mode boot, and no Win95 boot film.
    func testWindowsNT4Theme() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let bundle = root.appendingPathComponent("Resources/Themes/WindowsNT4-Workstation.retromactheme")
        let c = try JSONDecoder().decode(DockThemeConfig.self, from: Data(contentsOf: bundle.appendingPathComponent("theme.json")))
        XCTAssertEqual(c.name, "Windows NT Workstation 4.0")
        XCTAssertEqual(c.desktopIcons?.map(\.name), ["My Computer", "Network Neighborhood", "Inbox", "Internet Explorer", "Recycle Bin", "My Briefcase"])
        XCTAssertEqual(c.dock.startMenuProfile, "nt4")
        XCTAssertEqual(c.dock.showQuickLaunch, false)
        XCTAssertEqual(c.boot, DockThemeConfig.BootDecl(firmware: "award451", os: "nt4"))
        XCTAssertNil(c.splashVideo)
        XCTAssertTrue(SplashController.hasOSBoot(c))
        for icon in c.desktopIcons ?? [] {
            XCTAssertTrue(FileManager.default.fileExists(atPath: bundle.appendingPathComponent("icons/\(icon.icon)").path), icon.icon)
        }
        let page = try String(contentsOf: root.appendingPathComponent("Resources/Widgets/Boot/Boot.html"), encoding: .utf8)
        XCTAssertTrue(page.contains("OS === 'nt4'"))
    }

    /// The boot page's URL is an absolute file URL even from a relative resource URL: the first
    /// live Firmware boot crashed on exactly that.
    func testBootPageURLIsAFileURL() throws {
        let relative = URL(fileURLWithPath: "Contents/Resources", relativeTo: URL(fileURLWithPath: "/Applications/RetroMac.app"))
        let url = try XCTUnwrap(SplashController.bootPageURL(resources: relative, query: ["firmware": "award451"]))
        XCTAssertTrue(url.isFileURL)
        XCTAssertEqual(url.path, "/Applications/RetroMac.app/Contents/Resources/Widgets/Boot/Boot.html")
        XCTAssertEqual(url.query, "firmware=award451")
    }

    /// Settings survive a round trip, and a field the app does not know yet keeps its default.
    func testBIOSPrefs() throws {
        var p = BIOSPrefs()
        p.quickPOST = false
        p.values["award451/Virus Warning"] = "Enabled"
        let back = decodeOverDefaults(try JSONEncoder().encode(p), BIOSPrefs())
        XCTAssertEqual(back, p)
        let partial = decodeOverDefaults(Data(#"{"floppySeek":false}"#.utf8), BIOSPrefs())
        XCTAssertEqual(partial?.floppySeek, false)
        XCTAssertEqual(partial?.quickPOST, true)
    }

    /// The host data are whole numbers and real: memory in KiB as the POST counts it.
    func testHostData() {
        let d = BootHostData.current(now: Date(timeIntervalSince1970: 0))
        let kib = d["memoryKiB"] as? Int ?? 0
        XCTAssertGreaterThan(kib, 1024 * 1024)
        XCTAssertEqual(kib, Int((SystemSampler.sysctlUInt64("hw.memsize") ?? 0) / 1024))
        XCTAssertFalse((d["model"] as? String ?? "").isEmpty)
        XCTAssertGreaterThan(d["cores"] as? Int ?? 0, 0)
        XCTAssertEqual((d["date"] as? String)?.count, 10)
    }
}
