import Foundation
import Darwin
import IOKit
import IOKit.ps

public final class SystemReader {
    private var previousCPU: CPUTicks?
    private var volumes: [StorageVolume] = []
    private var lastStorageRead = Date.distantPast
    public init() {}

    public func read(refreshStorage: Bool = false) -> SystemSnapshot {
        var usage: Double?
        if let ticks = Self.cpuTicks() {
            if let previousCPU { usage = ticks.usage(since: previousCPU) }
            previousCPU = ticks
        }
        if refreshStorage || Date().timeIntervalSince(lastStorageRead) >= 15 {
            volumes = Self.storageVolumes(); lastStorageRead = .now
        }
        return SystemSnapshot(cpu: usage, memoryUsed: Self.memoryUsed(),
                              memoryTotal: ProcessInfo.processInfo.physicalMemory,
                              battery: Self.battery(), volumes: volumes)
    }

    public static func cpuTicks() -> CPUTicks? {
        let host = mach_host_self()
        defer { mach_port_deallocate(mach_task_self_, host) }
        var info = host_cpu_load_info()
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(host, HOST_CPU_LOAD_INFO, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }
        return CPUTicks(busy: UInt64(info.cpu_ticks.0) + UInt64(info.cpu_ticks.1) + UInt64(info.cpu_ticks.3),
                        idle: UInt64(info.cpu_ticks.2))
    }

    public static func memoryUsed() -> UInt64? {
        let host = mach_host_self()
        defer { mach_port_deallocate(mach_task_self_, host) }
        var vm = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &vm) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(host, HOST_VM_INFO64, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }
        var pageSize: vm_size_t = 0
        guard host_page_size(host, &pageSize) == KERN_SUCCESS else { return nil }
        let internalPages = UInt64(vm.internal_page_count)
        let appPages = internalPages > UInt64(vm.purgeable_count) ? internalPages - UInt64(vm.purgeable_count) : 0
        return (appPages + UInt64(vm.wire_count) + UInt64(vm.compressor_page_count)) * UInt64(pageSize)
    }

    public static func battery() -> BatteryReading? {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] else { return nil }
        for source in sources {
            guard let d = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue() as? [String: Any],
                  d[kIOPSTypeKey] as? String == kIOPSInternalBatteryType,
                  let current = d[kIOPSCurrentCapacityKey] as? Int,
                  let maxCapacity = d[kIOPSMaxCapacityKey] as? Int, maxCapacity > 0 else { continue }
            return BatteryReading(fraction: min(1, max(0, Double(current) / Double(maxCapacity))),
                                  charging: d[kIOPSIsChargingKey] as? Bool ?? false,
                                  onAC: d[kIOPSPowerSourceStateKey] as? String == kIOPSACPowerValue)
        }
        return nil
    }

    public static func storageVolumes() -> [StorageVolume] {
        let keys: Set<URLResourceKey> = [.volumeNameKey, .volumeUUIDStringKey, .volumeIsInternalKey,
                                        .volumeIsLocalKey, .volumeTotalCapacityKey, .volumeAvailableCapacityKey]
        let urls = FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: Array(keys),
                                                       options: [.skipHiddenVolumes]) ?? []
        var result: [StorageVolume] = []
        var seen = Set<String>()
        for url in [URL(fileURLWithPath: "/")] + urls {
            guard let v = try? url.resourceValues(forKeys: keys), v.volumeIsLocal == true else { continue }
            let isRoot = url.path == "/"
            // APFS support volumes, simulator images and hidden mounts are not user storage.
            guard isRoot || url.path.hasPrefix("/Volumes/") else { continue }
            guard let total = v.volumeTotalCapacity, total > 0,
                  let available = v.volumeAvailableCapacity else { continue }
            let id = isRoot ? "internal" : "volume:\(v.volumeUUIDString ?? url.path)"
            guard seen.insert(id).inserted else { continue }
            result.append(StorageVolume(id: id, name: v.volumeName ?? url.lastPathComponent,
                                        path: url.path, total: Int64(total), available: Int64(available),
                                        isInternal: isRoot || (v.volumeIsInternal ?? false)))
        }
        return result.sorted { lhs, rhs in
            if lhs.id == "internal" { return true }
            if rhs.id == "internal" { return false }
            return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
        }
    }

    public static func systemSleepDisabled() -> Bool? {
        let entry = IORegistryEntryFromPath(kIOMainPortDefault, "IOPower:/IOPowerConnection/IOPMrootDomain")
        guard entry != 0 else { return nil }
        defer { IOObjectRelease(entry) }
        // An absent property on an accessible root domain means the default: sleep enabled.
        guard let value = IORegistryEntryCreateCFProperty(entry, "SleepDisabled" as CFString,
                                                          kCFAllocatorDefault, 0)?.takeRetainedValue() else { return false }
        return (value as? NSNumber)?.boolValue
    }
}
