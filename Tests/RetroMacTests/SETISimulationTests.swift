import XCTest
@testable import RetroMac

/// The SETI@home simulation's rules from the spec: progress, counting, the random find, saving.
final class SETISimulationTests: XCTestCase {

    private func started(seed: UInt64 = 42) -> SETIState {
        var s = SETIState(seed: seed); s.started = true; return s
    }
    private func run(_ s: inout SETIState, seconds: Double, visible: Bool = true, speed: SETISimulation.Speed = .demo,
                     candidates: Bool = true, ask: Bool = false, onTick: ((SETIState) -> Void)? = nil) {
        var t = 0.0
        while t < seconds {
            SETISimulation.advance(&s, by: 0.5, visible: visible, speed: speed, candidates: candidates,
                                   frequency: .standard, askBeforeConnecting: ask)
            onTick?(s); t += 0.5
        }
    }

    /// Overall progress never goes back within a unit, and a unit is counted exactly once,
    /// after it was sent (AB-08, AB-17).
    func testOverallIsMonotonicAndUnitCountedOnce() {
        var s = started()
        var last = 0.0, unit = s.unitIndex
        run(&s, seconds: 600) { st in
            if st.unitIndex == unit { XCTAssertGreaterThanOrEqual(SETISimulation.overall(st), last - 1e-9) }
            else { unit = st.unitIndex }
            last = st.unitIndex == unit ? SETISimulation.overall(st) : 0
        }
        XCTAssertEqual(s.unitsDone, s.unitIndex, "one count per finished unit")
        XCTAssertGreaterThanOrEqual(s.unitsDone, 1, "demo speed finishes a unit in minutes")
        XCTAssertLessThanOrEqual(s.unitsDone, 3)
    }

    /// Pause, not started, or a huge gap: nothing runs away (AB-10, spec 8.3).
    func testPauseAndGapsHoldTheState() {
        var s = started(); s.paused = true
        let before = s
        SETISimulation.advance(&s, by: 50, visible: true, speed: .demo, candidates: true, frequency: .standard)
        XCTAssertEqual(s, before)
        var fresh = SETIState(seed: 1)
        SETISimulation.advance(&fresh, by: 50, visible: true, speed: .demo, candidates: true, frequency: .standard)
        XCTAssertEqual(fresh.phaseProgress, 0, "Ready: no processing before the start")
        var t = started()
        SETISimulation.advance(&t, by: 100_000, visible: true, speed: .demo, candidates: true, frequency: .standard)
        XCTAssertEqual(t.unitsDone, 0, "coming back after a day does not race through units")
    }

    /// The random find: not before 2 + 4 visible minutes, not while nobody watches, never twice
    /// within 5 minutes (spec 6.3).
    func testRandomFindRules() {
        var hidden = started()
        run(&hidden, seconds: 3600, visible: false)
        XCTAssertEqual(hidden.eventsSeen, 0, "invisible time does not count")
        XCTAssertEqual(hidden.visibleSeconds, 0)

        var s = started(seed: 7)
        var times: [Double] = []
        run(&s, seconds: 3 * 3600) { st in
            if st.current?.appearedAt == st.visibleSeconds { times.append(st.visibleSeconds) }
        }
        XCTAssertFalse(times.isEmpty)
        XCTAssertGreaterThanOrEqual(times[0], 360, "first find after 2 + at least 4 minutes")
        XCTAssertLessThanOrEqual(times[0], 120 + 720 + 60)
        for (a, b) in zip(times, times.dropFirst()) { XCTAssertGreaterThanOrEqual(b - a, 300) }

        var off = started(seed: 7)
        run(&off, seconds: 3 * 3600, candidates: false)
        XCTAssertEqual(off.eventsSeen, 0, "switched off: no staged finds (AB-20)")
    }

    /// The same seed draws the same sky: units, finds and their schedule repeat (ANI-13).
    func testReproducible() {
        var a = started(seed: 99), b = started(seed: 99)
        run(&a, seconds: 1800); run(&b, seconds: 1800)
        XCTAssertEqual(a, b)
        XCTAssertEqual(SETISimulation.makeUnit(seed: 5, index: 3), SETISimulation.makeUnit(seed: 5, index: 3))
        XCTAssertNotEqual(SETISimulation.makeUnit(seed: 5, index: 3), SETISimulation.makeUnit(seed: 5, index: 4))
    }

    /// A forced find matches the step it appears in: a lone spike is not passed off as a
    /// Gaussian (spec 6.2, AB-18), and recordings are dated in the project's years (spec 4.3).
    func testForcedFindAndUnitData() {
        var s = started()
        while SETISimulation.phase(s).step != .gaussians { SETISimulation.advance(&s, by: 1, visible: true, speed: .demo, candidates: false, frequency: .standard) }
        SETISimulation.stageFind(&s)
        XCTAssertEqual(s.current?.kind, .gaussian)
        XCTAssertEqual(s.best["gaussian"], s.current, "a strong find becomes the best")
        while SETISimulation.phase(s).step != .fft { SETISimulation.advance(&s, by: 1, visible: true, speed: .demo, candidates: false, frequency: .standard) }
        SETISimulation.stageFind(&s)
        XCTAssertEqual(s.current?.kind, .spike)
        for i in 0..<50 {
            let u = SETISimulation.makeUnit(seed: 3, index: i)
            let year = Calendar(identifier: .gregorian).component(.year, from: u.recordedAt)
            XCTAssertTrue((1999...2005).contains(year))
            XCTAssertEqual((u.baseFrequencyHz - 1.418e9).truncatingRemainder(dividingBy: 9765.625), 0, accuracy: 1e-3, "on the subband grid")
        }
    }

    /// "Ask before connecting": the transfer waits for Connect (MAC-03).
    func testAskBeforeConnectingWaits() {
        var s = started()
        run(&s, seconds: 30, ask: true)
        XCTAssertTrue(s.awaitingConnection)
        XCTAssertEqual(SETISimulation.phase(s).step, .connecting)
        SETISimulation.connect(&s)
        run(&s, seconds: 30, ask: true)
        XCTAssertNotEqual(SETISimulation.phase(s).step, .connecting)
    }

    /// Saved and read back the same; a damaged file starts afresh instead of hanging (spec 9.3);
    /// the state stays the same size however long it runs (spec 10.3).
    func testSavingAndRecovery() throws {
        var s = started(seed: 11)
        run(&s, seconds: 900)
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("seti-state.json")
        try JSONEncoder().encode(s).write(to: url)
        let (back, recovered) = SETIController.load(from: url)
        XCTAssertEqual(back, s); XCTAssertFalse(recovered)
        try Data("not json".utf8).write(to: url)
        let (fresh, wasDamaged) = SETIController.load(from: url)
        XCTAssertTrue(wasDamaged); XCTAssertEqual(fresh.unitsDone, 0)
        let small = try JSONEncoder().encode(s).count
        run(&s, seconds: 4 * 3600)
        XCTAssertLessThan(try JSONEncoder().encode(s).count, small * 2, "no growing history")
    }
}
