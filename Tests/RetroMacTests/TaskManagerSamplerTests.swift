import XCTest
@testable import RetroMac

/// The Task Manager's Performance page is only as right as the arithmetic behind it.
final class TaskManagerSamplerTests: XCTestCase {

    private typealias T = SystemSampler.Ticks

    func testCPULoadIsBusyTicksOverAllTicksAndKernelIsTheSystemShare() {
        let a = T(user: 100, system: 50, idle: 800, nice: 0)
        let b = T(user: 130, system: 70, idle: 850, nice: 0)   // +30 user, +20 system, +50 idle
        let l = SystemSampler.load(from: a, to: b)!
        XCTAssertEqual(l.busy, 50, accuracy: 0.001)
        XCTAssertEqual(l.kernel, 20, accuracy: 0.001)
    }

    func testNoTimePassedGivesNoReading() {
        let a = T(user: 1, system: 1, idle: 1, nice: 1)
        XCTAssertNil(SystemSampler.load(from: a, to: a))
    }

    func testCommitIsPromisedMemoryPlusSwapAndTheLimitIsRAMPlusSwap() {
        let c = SystemSampler.commit(activePages: 100, wiredPages: 50, compressorPages: 10, pageSize: 16384,
                                     swapUsed: 1 << 20, swapTotal: 1 << 30, physical: 8 << 30)
        XCTAssertEqual(c.charge, (160 * 16384 + (1 << 20)) / 1024)
        XCTAssertEqual(c.limit, ((8 << 30) + (1 << 30)) / 1024)
    }

    /// A live reading: sane ranges, and a page payload that is valid JSON.
    func testALiveSnapshotIsSaneAndItsJSONParses() throws {
        let sampler = SystemSampler()
        _ = sampler.next()
        let s = sampler.next()
        XCTAssert((0...100).contains(s.cpu))
        XCTAssertLessThanOrEqual(s.kernel, s.cpu + 0.001)
        XCTAssertGreaterThan(s.physTotalK, 0)
        XCTAssertLessThanOrEqual(s.physAvailK, s.physTotalK)
        XCTAssertGreaterThan(s.processes, 0)
        XCTAssertGreaterThanOrEqual(s.commitPeakK, s.commitK)
        let obj = try JSONSerialization.jsonObject(with: Data(s.json.utf8)) as? [String: Any]
        XCTAssertNotNil(obj?["commitLimit"])
        XCTAssertEqual((obj?["cores"] as? [Any])?.count, s.perCore.count)
    }
}
