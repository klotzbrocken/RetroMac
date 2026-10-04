import AppKit
import Darwin
import SystemConfiguration

/// The lists behind Task Manager's other pages — Applications, Processes, Networking, Users —
/// read from macOS. Each `next()` returns plain dictionaries for the page's JSON.

/// Applications: the programs with a Dock presence, as XP listed the windows on the taskbar.
enum TaskApplications {
    static func list() -> [[String: Any]] {
        NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular && $0.processIdentifier != getpid() }
            .map { app in
                ["pid": Int(app.processIdentifier),
                 "name": app.localizedName ?? app.bundleIdentifier ?? "?",
                 "icon": icon(for: app),
                 "status": "Running"]   // some apps never report "finished launching"
            }
            .sorted { ($0["name"] as! String).localizedCaseInsensitiveCompare($1["name"] as! String) == .orderedAscending }
    }

    private static var iconCache: [String: String] = [:]
    /// The theme's icon for the app (as on the taskbar), 16 pt, as a data URL; cached per app.
    private static func icon(for app: NSRunningApplication) -> String {
        let key = app.bundleIdentifier ?? "pid\(app.processIdentifier)"
        if let c = iconCache[key] { return c }
        let img = app.bundleIdentifier.map { ThemeManager.shared.icon(for: $0, size: 32) } ?? app.icon
        var url = ""
        if let img, let tiff = img.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
           let png = rep.representation(using: .png, properties: [:]) {
            url = "data:image/png;base64," + png.base64EncodedString()
        }
        iconCache[key] = url
        return url
    }
}

/// Processes: image name, user, CPU share since the last reading, resident memory.
final class TaskProcesses {
    private var lastCPU: [pid_t: UInt64] = [:]   // ns of CPU time
    private var lastWall: UInt64 = 0
    private var users: [uid_t: String] = [:]
    private static let timebase: (numer: UInt64, denom: UInt64) = {
        var tb = mach_timebase_info_data_t(); mach_timebase_info(&tb)
        return (UInt64(tb.numer), UInt64(max(1, tb.denom)))
    }()
    private let cores = Double(max(1, ProcessInfo.processInfo.activeProcessorCount))

    func reset() { lastCPU = [:]; lastWall = 0 }

    func list(allUsers: Bool) -> [[String: Any]] {
        let me = getuid()
        let wall = DispatchTime.now().uptimeNanoseconds
        let dt = lastWall == 0 ? 0 : Double(wall - lastWall)
        var seen: [pid_t: UInt64] = [:]
        var rows: [[String: Any]] = []
        for pid in SystemSampler.allPIDs() {
            var bsd = proc_bsdshortinfo()
            let bs = Int32(MemoryLayout<proc_bsdshortinfo>.size)
            guard proc_pidinfo(pid, PROC_PIDT_SHORTBSDINFO, 0, &bsd, bs) == bs else { continue }
            let uid = bsd.pbsi_uid
            if !allUsers && uid != me { continue }
            var row: [String: Any] = ["pid": Int(pid), "name": Self.name(pid, bsd), "user": userName(uid)]
            var ti = proc_taskinfo()
            let ts = Int32(MemoryLayout<proc_taskinfo>.size)
            if proc_pidinfo(pid, PROC_PIDTASKINFO, 0, &ti, ts) == ts {
                let cpu = (ti.pti_total_user + ti.pti_total_system) * Self.timebase.numer / Self.timebase.denom
                seen[pid] = cpu
                if dt > 0, let was = lastCPU[pid], cpu >= was {
                    row["cpu"] = min(99, Int((Double(cpu - was) / dt / cores * 100).rounded()))
                } else { row["cpu"] = 0 }
                row["mem"] = Int(ti.pti_resident_size / 1024)
            }
            // Processes of other users tell their name and owner only: no CPU, no memory.
            rows.append(row)
        }
        lastCPU = seen; lastWall = wall
        return rows
    }

    private static func name(_ pid: pid_t, _ bsd: proc_bsdshortinfo) -> String {
        var buf = [CChar](repeating: 0, count: 256)
        if proc_name(pid, &buf, UInt32(buf.count)) > 0 { return String(cString: buf) }
        var comm = bsd.pbsi_comm
        return withUnsafeBytes(of: &comm) { String(cString: $0.bindMemory(to: CChar.self).baseAddress!) }
    }

    private func userName(_ uid: uid_t) -> String {
        if let n = users[uid] { return n }
        let n = getpwuid(uid).map { String(cString: $0.pointee.pw_name) } ?? String(uid)
        users[uid] = n
        return n
    }
}

/// Networking: one row per connected adapter, its use as a share of the link speed.
final class TaskNetwork {
    private var last: [String: (bytes: UInt64, at: UInt64)] = [:]

    func list() -> [[String: Any]] {
        var ifap: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifap) == 0, let first = ifap else { return [] }
        defer { freeifaddrs(ifap) }
        var withAddress = Set<String>()
        var links: [(name: String, bytes: UInt64, baud: UInt64)] = []
        for p in sequence(first: first, next: { $0.pointee.ifa_next }) {
            let a = p.pointee
            let name = String(cString: a.ifa_name)
            let flags = Int32(a.ifa_flags)
            guard flags & IFF_UP != 0, flags & IFF_RUNNING != 0, flags & IFF_LOOPBACK == 0,
                  let sa = a.ifa_addr else { continue }
            switch Int32(sa.pointee.sa_family) {
            case AF_INET, AF_INET6: withAddress.insert(name)
            case AF_LINK:
                guard let data = a.ifa_data?.assumingMemoryBound(to: if_data.self).pointee else { continue }
                links.append((name, UInt64(data.ifi_ibytes) + UInt64(data.ifi_obytes), UInt64(data.ifi_baudrate)))
            default: break
            }
        }
        let names = Self.displayNames()
        let now = DispatchTime.now().uptimeNanoseconds
        var rows: [[String: Any]] = []
        for l in links where withAddress.contains(l.name) && names[l.name] != nil {
            var util = 0.0
            if let was = last[l.name], l.bytes >= was.bytes, now > was.at, l.baud > 0 {
                let bps = Double(l.bytes - was.bytes) * 8 / (Double(now - was.at) / 1e9)
                util = min(100, bps / Double(l.baud) * 100)
            }
            last[l.name] = (l.bytes, now)
            rows.append(["id": l.name, "name": names[l.name]!, "util": util,
                         "speed": Self.speed(l.baud), "state": "Connected"])
        }
        return rows
    }

    /// "Wi-Fi", "Ethernet", "Thunderbolt Bridge" — the names System Settings uses. Only
    /// hardware adapters have one, which leaves out tunnels and the like.
    private static func displayNames() -> [String: String] {
        var out: [String: String] = [:]
        for i in (SCNetworkInterfaceCopyAll() as? [SCNetworkInterface]) ?? [] {
            if let bsd = SCNetworkInterfaceGetBSDName(i) as String?, let n = SCNetworkInterfaceGetLocalizedDisplayName(i) as String? {
                out[bsd] = n
            }
        }
        return out
    }

    static func speed(_ baud: UInt64) -> String {
        if baud >= 1_000_000_000 { return String(format: "%g Gbps", (Double(baud) / 1e9 * 10).rounded() / 10) }
        if baud >= 1_000_000 { return "\(baud / 1_000_000) Mbps" }
        if baud >= 1_000 { return "\(baud / 1_000) Kbps" }
        return baud > 0 ? "\(baud) bps" : "—"
    }
}

/// Users: who is logged in at this Mac (the console sessions in utmpx), as XP's Fast User
/// Switching listed them.
enum TaskUsers {
    static func list() -> [[String: Any]] {
        var names: [String] = []
        setutxent()
        while let e = getutxent() {
            guard e.pointee.ut_type == USER_PROCESS else { continue }
            var line = e.pointee.ut_line
            let tty = withUnsafeBytes(of: &line) { String(cString: $0.bindMemory(to: CChar.self).baseAddress!) }
            guard tty == "console" else { continue }
            var user = e.pointee.ut_user
            let n = withUnsafeBytes(of: &user) { String(cString: $0.bindMemory(to: CChar.self).baseAddress!) }
            if !n.isEmpty, !names.contains(n) { names.append(n) }
        }
        endutxent()
        if !names.contains(NSUserName()) { names.insert(NSUserName(), at: 0) }
        return names.enumerated().map { i, n in
            ["user": n, "id": i, "status": n == NSUserName() ? "Active" : "Disconnected", "session": "Console"]
        }
    }
}
