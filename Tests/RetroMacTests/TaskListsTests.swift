import XCTest
@testable import RetroMac

final class TaskListsTests: XCTestCase {
    func testOwnProcessIsListedWithItsMemory() {
        let rows = TaskProcesses().list(allUsers: false)
        let me = rows.first { ($0["pid"] as? Int) == Int(getpid()) }
        XCTAssertNotNil(me)
        XCTAssertGreaterThan(me?["mem"] as? Int ?? 0, 0)
        XCTAssertEqual(me?["user"] as? String, NSUserName())
    }

    func testOtherUsersOnlyWhenAsked() {
        let mine = TaskProcesses().list(allUsers: false)
        XCTAssertTrue(mine.allSatisfy { $0["user"] as? String == NSUserName() })
        let all = TaskProcesses().list(allUsers: true)
        XCTAssertTrue(all.contains { $0["user"] as? String == "root" })
    }

    func testLinkSpeedReadsLikeXP() {
        XCTAssertEqual(TaskNetwork.speed(1_000_000_000), "1 Gbps")
        XCTAssertEqual(TaskNetwork.speed(866_000_000), "866 Mbps")
        XCTAssertEqual(TaskNetwork.speed(0), "—")
    }
}
