import Foundation
import Darwin

public struct ProcessReading: Identifiable, Equatable {
    public let pid: Int32
    public let startedAt: UInt64
    public let name: String
    public let cpuPercent: Double?
    public let residentBytes: UInt64
    public var id: String { "\(pid):\(startedAt)" }
}

public enum MemoryPressure: String {
    case normal = "Normal", warning = "Elevated", critical = "Critical", unknown = "Unavailable"
}

public struct ProcessSnapshot {
    public var processes: [ProcessReading] = []
    public var pressure: MemoryPressure = .unknown
    public var swapBytes: UInt64?
    public var compressedBytes: UInt64?
    public var sampledAt = Date.now
    public init() {}
}

/// Native, unprivileged process readings. All instances are confined to their sampling queue.
public final class ProcessReader {
    private var previous: [String: (cpu: UInt64, time: TimeInterval)] = [:]
    private let nanosecondsPerTick: Double
    public init() {
        var timebase = mach_timebase_info_data_t()
        mach_timebase_info(&timebase)
        nanosecondsPerTick = Double(timebase.numer) / Double(timebase.denom)
    }

    public static func cpuPercent(current: UInt64, previous: UInt64, elapsed: TimeInterval, nanosecondsPerTick: Double = 1) -> Double? {
        guard current >= previous, elapsed > 0, elapsed.isFinite else { return nil }
        return Double(current - previous) * nanosecondsPerTick / (elapsed * 1_000_000_000) * 100
    }

    public func reset() { previous.removeAll() }

    public func read() -> ProcessSnapshot {
        var result = ProcessSnapshot()
        let size = proc_listpids(UInt32(PROC_ALL_PIDS), 0, nil, 0)
        guard size > 0 else { return result }
        var pids = [Int32](repeating: 0, count: Int(size) / MemoryLayout<Int32>.size + 256)
        let bytes = pids.withUnsafeMutableBytes { proc_listpids(UInt32(PROC_ALL_PIDS), 0, $0.baseAddress, Int32($0.count)) }
        let now = ProcessInfo.processInfo.systemUptime
        var next: [String: (cpu: UInt64, time: TimeInterval)] = [:]
        for pid in pids.prefix(max(0, Int(bytes) / MemoryLayout<Int32>.size)) where pid > 0 {
            var info = proc_taskallinfo()
            guard proc_pidinfo(pid, PROC_PIDTASKALLINFO, 0, &info, Int32(MemoryLayout.size(ofValue: info))) == MemoryLayout.size(ofValue: info) else { continue }
            let start = info.pbsd.pbi_start_tvsec * 1_000_000 + info.pbsd.pbi_start_tvusec
            let key = "\(pid):\(start)"
            // XNU fill_taskprocinfo reports mach time ticks, not nanoseconds (notably on Apple silicon).
            let cpu = info.ptinfo.pti_total_user &+ info.ptinfo.pti_total_system
            let percent = previous[key].flatMap { Self.cpuPercent(current: cpu, previous: $0.cpu, elapsed: now - $0.time, nanosecondsPerTick: nanosecondsPerTick) }
            next[key] = (cpu, now)
            var name = [CChar](repeating: 0, count: 1024)
            let length = proc_name(pid, &name, UInt32(name.count))
            let title = length > 0 ? String(cString: name) : "Process \(pid)"
            result.processes.append(ProcessReading(pid: pid, startedAt: start, name: title,
                                                   cpuPercent: percent, residentBytes: info.ptinfo.pti_resident_size))
        }
        previous = next
        var pressure: Int32 = 0
        var pressureSize = MemoryLayout.size(ofValue: pressure)
        if sysctlbyname("kern.memorystatus_vm_pressure_level", &pressure, &pressureSize, nil, 0) == 0 {
            result.pressure = pressure == 1 ? .normal : pressure == 2 ? .warning : pressure == 4 ? .critical : .unknown
        }
        var swap = xsw_usage()
        var swapSize = MemoryLayout.size(ofValue: swap)
        if sysctlbyname("vm.swapusage", &swap, &swapSize, nil, 0) == 0 { result.swapBytes = swap.xsu_used }
        let host = mach_host_self()
        defer { mach_port_deallocate(mach_task_self_, host) }
        var vm = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout.size(ofValue: vm) / MemoryLayout<integer_t>.size)
        let status = withUnsafeMutablePointer(to: &vm) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { host_statistics64(host, HOST_VM_INFO64, $0, &count) }
        }
        var page: vm_size_t = 0
        if status == KERN_SUCCESS, host_page_size(host, &page) == KERN_SUCCESS {
            result.compressedBytes = UInt64(vm.compressor_page_count) * UInt64(page)
        }
        return result
    }
}
