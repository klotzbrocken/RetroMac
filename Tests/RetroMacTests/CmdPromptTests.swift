import XCTest
@testable import RetroMac

final class CmdPromptTests: XCTestCase {

    /// A real zsh with an empty home: the prompt is the Command Prompt's, and the user's own
    /// .zshrc still runs.
    func testZshGetsTheCommandPromptAndStillRunsTheUsersFiles() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("cmdprompt-\(UUID().uuidString)")
        let dot = root.appendingPathComponent("cmd-zsh"), home = root.appendingPathComponent("home")
        let work = home.appendingPathComponent("src 50%")
        try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        XCTAssertTrue(CmdPrompt.install(into: dot))
        try "export RM_TEST_MARK=users-zshrc\n".write(to: home.appendingPathComponent(".zshrc"), atomically: true, encoding: .utf8)

        let zsh = Process()
        zsh.executableURL = URL(fileURLWithPath: "/bin/zsh")
        zsh.arguments = ["-i", "-c", "print -r -- \"$RM_TEST_MARK|${(%)PS1}\""]
        zsh.environment = ["HOME": home.path, "ZDOTDIR": dot.path, "PATH": "/usr/bin:/bin", "TERM": "dumb"]
        zsh.currentDirectoryURL = work
        let out = Pipe()
        zsh.standardOutput = out
        zsh.standardError = Pipe()
        try zsh.run()
        zsh.waitUntilExit()
        let text = String(decoding: out.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        let line = text.split(separator: "\n").last.map(String.init) ?? ""
        // The user's .zshrc ran, and the folder (with a % in its name) reads the Windows way.
        XCTAssertTrue(line.hasPrefix("users-zshrc|C:\\"), line)
        XCTAssertTrue(line.hasSuffix("\\home\\src 50%>"), line)
        XCTAssertFalse(line.contains("/"), line)
    }

    func testQuotingSurvivesQuotes() {
        XCTAssertEqual(CmdPrompt.quoted("it's"), "'it'\\''s'")
    }
}
