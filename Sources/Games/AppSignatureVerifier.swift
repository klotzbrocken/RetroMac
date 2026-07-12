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

    /// Reads a bundle's code-signing identity via `codesign -dv --verbose=4` (which writes to
    /// stderr). Used to enforce a per-download allowlist so a compromised endpoint can't swap in a
    /// DIFFERENT (but still notarized) app. Returns nil fields when unsigned/unreadable.
    static func readIdentity(at path: String) -> (teamID: String?, bundleID: String?) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/codesign")
        p.arguments = ["-dv", "--verbose=4", path]
        let err = Pipe()
        p.standardError = err
        p.standardOutput = FileHandle.nullDevice
        do { try p.run() } catch { return (nil, nil) }
        // Read BEFORE waitUntilExit so a large output can't deadlock on a full pipe buffer.
        let data = err.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        let text = String(data: data, encoding: .utf8) ?? ""
        var team: String?
        var bundle: String?
        for raw in text.split(separator: "\n") {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("TeamIdentifier=") {
                team = String(line.dropFirst("TeamIdentifier=".count)).trimmingCharacters(in: .whitespaces)
            } else if line.hasPrefix("Identifier=") {
                bundle = String(line.dropFirst("Identifier=".count)).trimmingCharacters(in: .whitespaces)
            }
        }
        if team == "not set" { team = nil }   // codesign prints this for ad-hoc/unsigned
        return (team, bundle)
    }
}
