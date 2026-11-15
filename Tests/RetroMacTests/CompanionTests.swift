import XCTest
@testable import RetroMac

/// The desktop companion: reading clippy.js's agent files, stepping through animations like its
/// Animator, the download table, and the small rules behind the clipboard, calendar, watcher and tips.
final class CompanionTests: XCTestCase {

    private var agents: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Resources/Agents")
    }

    private func fresh(_ name: String = #function) -> UserDefaults {
        let suite = "CompanionTests.\(name)"
        UserDefaults().removePersistentDomain(forName: suite)
        return UserDefaults(suiteName: suite)!
    }

    // MARK: Agent files

    func testBundledAgentsLoadAndKnowEveryMoment() throws {
        for name in AgentCatalog.bundled {
            let c = try XCTUnwrap(AgentCharacter.load(name: name, from: agents.appendingPathComponent(name)), name)
            XCTAssertEqual(c.frameSize, CGSize(width: 124, height: 93), name)
            XCTAssertFalse(c.idleAnimations.isEmpty, name)
            XCTAssertFalse(c.sounds.isEmpty, name)
            for m in AgentCharacter.Moment.allCases {
                XCTAssertNotNil(c.animation(for: m), "\(name) has nothing for \(m)")
            }
            // Every sprite position lies on the sheet and every branch inside its animation.
            for (anim, a) in c.animations {
                for f in a.frames {
                    for xy in f.images ?? [] {
                        XCTAssertLessThanOrEqual(xy[0] + 124, c.sheet.width, "\(name)/\(anim)")
                        XCTAssertLessThanOrEqual(xy[1] + 93, c.sheet.height, "\(name)/\(anim)")
                    }
                    for b in f.branching?.branches ?? [] { XCTAssertLessThan(b.frameIndex, a.frames.count) }
                    if let s = f.sound { XCTAssertNotNil(c.sounds[s], "\(name)/\(anim) sound \(s)") }
                }
            }
        }
    }

    func testWrappersAreStripped() {
        let js = "clippy.ready('X', {\"overlayCount\":2,\"framesize\":[10,20],\"animations\":{\"A\":{\"frames\":[{\"duration\":100}]}}});"
        let parsed = AgentCharacter.parseAnimations(js)
        XCTAssertEqual(parsed?.0, CGSize(width: 10, height: 20))
        XCTAssertEqual(parsed?.1, 2)
        XCTAssertNil(AgentCharacter.parseAnimations("clippy.ready('X', {});"))
        let sounds = AgentCharacter.parseSounds("clippy.soundsReady('X', {'1':'data:audio/mpeg;base64,AAEC','2':'nope'})")
        XCTAssertEqual(sounds["1"], Data([0, 1, 2]))
        XCTAssertNil(sounds["2"])
    }

    func testDownloadTableCoversEveryFile() {
        XCTAssertFalse(AgentCatalog.all.contains("Bonzi"))
        for name in AgentCatalog.downloadable {
            for file in AgentCatalog.files { XCTAssertEqual(AgentCatalog.sha256["\(name)/\(file)"]?.count, 64, "\(name)/\(file)") }
        }
        XCTAssertEqual(AgentCatalog.sha256.count, AgentCatalog.downloadable.count * AgentCatalog.files.count)
        XCTAssertFalse(AgentCatalog.verify(Data("tampered".utf8), path: "Rover/map.png"))
        XCTAssertFalse(AgentCatalog.verify(Data(), path: "Clippy/map.png"))   // bundled ones are never fetched
    }

    // MARK: Animator

    private func frame(_ exit: Int? = nil, _ branches: [(Int, Int)] = []) -> AgentCharacter.Frame {
        .init(duration: 100, images: [[0, 0]], sound: nil, exitBranch: exit,
              branching: branches.isEmpty ? nil : .init(branches: branches.map { .init(frameIndex: $0.0, weight: $0.1) }))
    }

    func testAnimatorBranchesByWeightAndLeavesThroughExitBranch() {
        // 0 → 1; 1 loops on itself 90 % of the time, else goes on; leaving jumps from 1 to 3.
        let a = AgentCharacter.Animation(frames: [frame(), frame(3, [(1, 90)]), frame(), frame()], useExitBranching: nil)
        var an = AgentAnimator(a)
        XCTAssertEqual(an.step(roll: 0), .none); XCTAssertEqual(an.index, 0)
        XCTAssertEqual(an.step(roll: 0), .none); XCTAssertEqual(an.index, 1)
        XCTAssertEqual(an.step(roll: 50), .none); XCTAssertEqual(an.index, 1)    // inside the 90
        XCTAssertEqual(an.step(roll: 95), .none); XCTAssertEqual(an.index, 2)    // past it
        var out = AgentAnimator(a)
        _ = out.step(roll: 0); _ = out.step(roll: 0)
        out.exiting = true
        XCTAssertEqual(out.step(roll: 0), .exited)
        XCTAssertEqual(out.index, 3)
    }

    func testAnimationWithExitBranchingWaitsOnItsLastFrame() {
        let a = AgentCharacter.Animation(frames: [frame(), frame()], useExitBranching: true)
        var an = AgentAnimator(a)
        _ = an.step(roll: 0)
        XCTAssertEqual(an.step(roll: 0), .waiting)
        XCTAssertEqual(an.step(roll: 0), .none)   // holds there
    }

    // MARK: Choice

    func testMatchTheTheme() {
        XCTAssertEqual(CompanionController.resolved("theme", themeName: "Windows 98"), "Clippy")
        XCTAssertEqual(CompanionController.resolved("theme", themeName: "Windows NT 4.0"), "Clippy")
        XCTAssertNil(CompanionController.resolved("theme", themeName: "Mac OS 9 Authentic"))
        XCTAssertNil(CompanionController.resolved("theme", themeName: nil))
        XCTAssertEqual(CompanionController.resolved("Genius", themeName: nil), "Genius")   // works without a theme
        XCTAssertNil(CompanionController.resolved("sheep", themeName: "Windows XP"))
        XCTAssertNil(CompanionController.resolved("Bonzi", themeName: nil))
    }

    func testPrefsKeepDefaultsForMissingKeys() throws {
        let p = try XCTUnwrap(decodeOverDefaults(Data(#"{"character":"Genius"}"#.utf8), CompanionPrefs()))
        XCTAssertEqual(p.character, "Genius")
        XCTAssertTrue(p.clipboard)
        XCTAssertFalse(p.calendar)   // needs a permission, so it starts off
        XCTAssertFalse(p.sounds)
    }

    // MARK: Jobs

    func testClipboardKeepsTenDistinctTexts() {
        var items: [String] = []
        for i in 0..<12 { ClipboardHistory.insert("t\(i)", into: &items) }
        ClipboardHistory.insert("t5", into: &items)
        ClipboardHistory.insert("   ", into: &items)
        XCTAssertEqual(items.count, 10)
        XCTAssertEqual(items.first, "t5")
        XCTAssertEqual(items.filter { $0 == "t5" }.count, 1)
        XCTAssertTrue(ClipboardHistory.skipped.contains("org.nspasteboard.ConcealedType"))
    }

    func testMeetingLinkPrefersVideoCalls() {
        XCTAssertEqual(CompanionCalendar.meetingLink([nil, "Room 4", "Agenda https://example.com/doc\nJoin: https://us02web.zoom.us/j/123?pwd=x"])?.host,
                       "us02web.zoom.us")
        XCTAssertEqual(CompanionCalendar.meetingLink(["https://meet.google.com/abc-defg-hij"])?.host, "meet.google.com")
        XCTAssertNil(CompanionCalendar.meetingLink(["https://example.com", "http://zoom.us/j/1"]))
    }

    func testOnlyFinishedDownloadsCount() {
        XCTAssertEqual(MacWatcher.finished(["b.zip", ".DS_Store", "a.dmg.download", "c.crdownload", "d.part", "a.pdf"]), ["a.pdf", "b.zip"])
    }

    func testDiskNearlyFull() {
        XCTAssertTrue(MacWatcher.diskNearlyFull(free: 5_000_000_000, total: 1_000_000_000_000))
        XCTAssertTrue(MacWatcher.diskNearlyFull(free: 20_000_000_000, total: 500_000_000_000))   // 4 %
        XCTAssertFalse(MacWatcher.diskNearlyFull(free: 100_000_000_000, total: 1_000_000_000_000))
    }

    func testLastBackupFromPreferences() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("tm.plist")
        let a = Date(timeIntervalSince1970: 1_000_000), b = Date(timeIntervalSince1970: 2_000_000)
        XCTAssertTrue(NSDictionary(dictionary: ["Destinations": [["SnapshotDates": [a, b]], ["SnapshotDates": [a]]]]).write(to: url, atomically: true))
        XCTAssertEqual(MacWatcher.lastBackup(plist: url), b)
        XCTAssertTrue(NSDictionary(dictionary: ["PreferencesVersion": 6]).write(to: url, atomically: true))
        XCTAssertNil(MacWatcher.lastBackup(plist: url))   // no Time Machine set up: no nagging
    }

    func testTipsAreOccasional() {
        let d = fresh()
        let t0 = Date(timeIntervalSince1970: 1_800_000_000)
        XCTAssertNotNil(CompanionTips.next(for: "com.apple.finder", now: t0, defaults: d))
        XCTAssertNil(CompanionTips.next(for: "com.apple.Safari", now: t0.addingTimeInterval(60), defaults: d))        // too soon
        XCTAssertNotNil(CompanionTips.next(for: "com.apple.Safari", now: t0.addingTimeInterval(21 * 60), defaults: d))
        XCTAssertNil(CompanionTips.next(for: "com.apple.finder", now: t0.addingTimeInterval(60 * 60), defaults: d))   // once a day
        XCTAssertNotNil(CompanionTips.next(for: "com.apple.finder", now: t0.addingTimeInterval(26 * 3600), defaults: d))
    }
}
