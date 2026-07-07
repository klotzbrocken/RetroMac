import Foundation

/// Shared Gatekeeper verification for downloaded `.app` bundles before they are installed.
///
/// Downloads happen over the network (curl / GitHub / archive.org), so a MITM, CDN, DNS or
/// build-bot compromise could serve a malicious binary. Before trusting a bundle we require:
///   1. an intact, unmodified code signature (`codesign --verify --deep --strict`), and
///   2. Gatekeeper acceptance (`spctl --assess --type execute` → Developer ID + notarized).
/// Both must return exit status 0.
enum AppSignatureVerifier {
    /// Returns true only if the bundle at `path` passes both codesign and Gatekeeper checks.
    /// Runs synchronously (call off the main thread) and never blocks on the checks failing.
    static func verifyAppSignature(at path: String) -> Bool {
        func run(_ tool: String, _ args: [String]) -> Bool {
            let p = Process()
            p.executableURL = URL(fileURLWithPath: tool)
            p.arguments = args
            p.standardOutput = FileHandle.nullDevice
            p.standardError = FileHandle.nullDevice
            do { try p.run() } catch { return false }
            p.waitUntilExit()
            return p.terminationStatus == 0
        }
        guard run("/usr/bin/codesign", ["--verify", "--deep", "--strict", path]) else { return false }
        return run("/usr/sbin/spctl", ["--assess", "--type", "execute", path])
    }
}
