import Darwin
import Foundation

/// What Windows XP's Task Manager shows on its Performance page, taken from macOS once a
/// second. Where macOS has no such thing the nearest it has stands in:
///
/// - **CPU Usage**: busy ticks over all ticks since the last sample; the kernel share is the
///   system ticks (Task Manager's red "kernel times").
/// - **PF Usage / Commit Charge**: memory the system has promised — active, wired and what the
///   compressor holds, plus swap in use. The limit is RAM plus swap; the peak is this session's.
/// - **Physical Memory**: total RAM; available is free, inactive and speculative pages; the
///   system cache is the file-backed pages.
/// - **Kernel Memory**: macOS pages no kernel memory out, so "nonpaged" is the wired memory and
///   "paged" what the compressor occupies.
/// - **Handles**: open files system-wide (kern.num_files). **Threads**: summed over the
///   processes this user may read — processes of other users (root) do not tell without
///   privileges, so the figure is the readable part, not an estimate.
struct SystemSnapshot: Equatable {
    var cpu: Double = 0          // 0…100
    var kernel: Double = 0       // 0…100, the kernel share of `cpu`
    var perCore: [Double] = []
    var physTotalK: UInt64 = 0
    var physAvailK: UInt64 = 0
    var systemCacheK: UInt64 = 0
    var commitK: UInt64 = 0
    var commitLimitK: UInt64 = 0
    var commitPeakK: UInt64 = 0
    var kernelPagedK: UInt64 = 0
    var kernelNonpagedK: UInt64 = 0
    var handles: Int = 0
    var threads: Int = 0
    var processes: Int = 0

    var kernelTotalK: UInt64 { kernelPagedK + kernelNonpagedK }

    /// The page for the web view, in the names the Performance page uses.
    var json: String {
        let cores = perCore.map { String(format: "%.1f", $0) }.joined(separator: ",")
        return """
        {"cpu":\(String(format: "%.1f", cpu)),"kernel":\(String(format: "%.1f", kernel)),"cores":[\(cores)],\
        "physTotal":\(physTotalK),"physAvail":\(physAvailK),"sysCache":\(systemCacheK),\
        "commit":\(commitK),"commitLimit":\(commitLimitK),"commitPeak":\(commitPeakK),\
        "kPaged":\(kernelPagedK),"kNonpaged":\(kernelNonpagedK),"kTotal":\(kernelTotalK),\
        "handles":\(handles),"threads":\(threads),"processes":\(processes)}
        """
    }
}

final class SystemSampler {

    struct Ticks: Equatable { var user: UInt64; var system: UInt64; var idle: UInt64; var nice: UInt64 }

    private var lastTotal: Ticks?
    private var lastCores: [Ticks] = []
    private var commitPeakK: UInt64 = 0

    func reset() { lastTotal = nil; lastCores = []; commitPeakK = 0 }

    /// Busy and kernel percentages between two tick readings. Nil when no time has passed.
    static func load(from a: Ticks, to b: Ticks) -> (busy: Double, kernel: Double)? {
        let user = Double(b.user &- a.user), sys = Double(b.system &- a.system)
        let idle = Double(b.idle &- a.idle), nice = Double(b.nice &- a.nice)
        let total = user + sys + idle + nice
        guard total > 0 else { return nil }
        return ((user + sys + nice) / total * 100, sys / total * 100)
    }

    /// Commit charge and its limit, in KB, from page counts and swap bytes.
    static func commit(activePages: UInt64, wiredPages: UInt64, compressorPages: UInt64, pageSize: UInt64,
                       swapUsed: UInt64, swapTotal: UInt64, physical: UInt64) -> (charge: UInt64, limit: UInt64) {
        let charge = (activePages + wiredPages + compressorPages) * pageSize + swapUsed
        return (charge / 1024, (physical + swapTotal) / 1024)
    }

    func next() -> SystemSnapshot {
        var s = SystemSnapshot()
        if let now = Self.totalTicks() {
            if let last = lastTotal, let l = Self.load(from: last, to: now) { s.cpu = l.busy; s.kernel = l.kernel }
            lastTotal = now
        }
        let cores = Self.coreTicks()
        if cores.count == lastCores.count {
            s.perCore = zip(lastCores, cores).map { Self.load(from: $0, to: $1)?.busy ?? 0 }
        } else {
            s.perCore = Array(repeating: 0, count: cores.count)
        }
        lastCores = cores

        let physical = Self.sysctlUInt64("hw.memsize") ?? 0
        s.physTotalK = physical / 1024
        if let vm = Self.vmStats() {
            let page = UInt64(vm_kernel_page_size)
            s.physAvailK = (UInt64(vm.free_count) + UInt64(vm.inactive_count) + UInt64(vm.speculative_count)) * page / 1024
            s.systemCacheK = UInt64(vm.external_page_count) * page / 1024
            let swap = Self.swapUsage()
            let c = Self.commit(activePages: UInt64(vm.active_count), wiredPages: UInt64(vm.wire_count),
                                compressorPages: UInt64(vm.compressor_page_count), pageSize: page,
                                swapUsed: swap.used, swapTotal: swap.total, physical: physical)
            s.commitK = c.charge
            s.commitLimitK = c.limit
            s.kernelPagedK = UInt64(vm.compressor_page_count) * page / 1024
            s.kernelNonpagedK = UInt64(vm.wire_count) * page / 1024
        }
        commitPeakK = max(commitPeakK, s.commitK)
        s.commitPeakK = commitPeakK

        s.handles = Int(Self.sysctlUInt64("kern.num_files") ?? 0)
        let pids = Self.allPIDs()
        s.processes = pids.count
        s.threads = pids.reduce(0) { sum, pid in
            var ti = proc_taskinfo()
            let size = Int32(MemoryLayout<proc_taskinfo>.size)
            return proc_pidinfo(pid, PROC_PIDTASKINFO, 0, &ti, size) == size ? sum + Int(ti.pti_threadnum) : sum
        }
        return s
    }

    // MARK: - Readings

    static func totalTicks() -> Ticks? {
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info_data_t>.stride / MemoryLayout<integer_t>.stride)
        var info = host_cpu_load_info_data_t()
        let kr = withUnsafeMutablePointer(to: &info) { ptr in
            ptr.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &count)
            }
        }
        guard kr == KERN_SUCCESS else { return nil }
        let t = info.cpu_ticks
        return Ticks(user: UInt64(t.0), system: UInt64(t.1), idle: UInt64(t.2), nice: UInt64(t.3))
    }

    static func coreTicks() -> [Ticks] {
        var cpuCount: natural_t = 0
        var info: processor_info_array_t?
        var infoCount: mach_msg_type_number_t = 0
        guard host_processor_info(mach_host_self(), PROCESSOR_CPU_LOAD_INFO, &cpuCount, &info, &infoCount) == KERN_SUCCESS,
              let info else { return [] }
        defer {
            vm_deallocate(mach_task_self_, vm_address_t(bitPattern: info), vm_size_t(Int(infoCount) * MemoryLayout<integer_t>.stride))
        }
        let n = Int(CPU_STATE_MAX)
        return (0..<Int(cpuCount)).map { i in
            let b = i * n
            return Ticks(user: UInt64(UInt32(bitPattern: info[b + Int(CPU_STATE_USER)])),
                         system: UInt64(UInt32(bitPattern: info[b + Int(CPU_STATE_SYSTEM)])),
                         idle: UInt64(UInt32(bitPattern: info[b + Int(CPU_STATE_IDLE)])),
                         nice: UInt64(UInt32(bitPattern: info[b + Int(CPU_STATE_NICE)])))
        }
    }

    static func vmStats() -> vm_statistics64? {
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.stride / MemoryLayout<integer_t>.stride)
        var vm = vm_statistics64()
        let kr = withUnsafeMutablePointer(to: &vm) { ptr in
            ptr.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        return kr == KERN_SUCCESS ? vm : nil
    }

    static func swapUsage() -> (used: UInt64, total: UInt64) {
        var sw = xsw_usage()
        var size = MemoryLayout<xsw_usage>.size
        guard sysctlbyname("vm.swapusage", &sw, &size, nil, 0) == 0 else { return (0, 0) }
        return (sw.xsu_used, sw.xsu_total)
    }

    static func allPIDs() -> [pid_t] {
        let n = proc_listallpids(nil, 0)
        guard n > 0 else { return [] }
        var pids = [pid_t](repeating: 0, count: Int(n) + 32)
        let got = proc_listallpids(&pids, Int32(pids.count * MemoryLayout<pid_t>.size))
        return pids.prefix(Int(max(0, got))).filter { $0 > 0 }
    }

    static func sysctlUInt64(_ name: String) -> UInt64? {
        var size = 0
        guard sysctlbyname(name, nil, &size, nil, 0) == 0 else { return nil }
        switch size {
        case 8: var v: UInt64 = 0; return sysctlbyname(name, &v, &size, nil, 0) == 0 ? v : nil
        case 4: var v: UInt32 = 0; return sysctlbyname(name, &v, &size, nil, 0) == 0 ? UInt64(v) : nil
        default: return nil
        }
    }
}
