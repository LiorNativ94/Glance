import Foundation

public struct CPUTicks {
    public let busy: UInt64
    public let idle: UInt64
    public init(busy: UInt64, idle: UInt64) { self.busy = busy; self.idle = idle }
    public func usage(since old: CPUTicks) -> Double? {
        guard busy >= old.busy, idle >= old.idle else { return nil }
        let work = busy - old.busy, rest = idle - old.idle
        guard work + rest > 0 else { return nil }
        return Double(work) / Double(work + rest)
    }
}

public struct StorageVolume: Identifiable, Equatable {
    public let id: String
    public let name: String
    public let path: String
    public let total: Int64
    public let available: Int64
    public let isInternal: Bool
    public var used: Int64 { max(0, total - available) }
    public var fraction: Double { total > 0 ? min(1, max(0, Double(used) / Double(total))) : 0 }
    public init(id: String, name: String, path: String, total: Int64, available: Int64, isInternal: Bool) {
        self.id = id; self.name = name; self.path = path; self.total = total
        self.available = max(0, min(total, available)); self.isInternal = isInternal
    }
}

/// Which mounts count as user storage.
public enum StorageFilter {
    /// The sealed system volume is read-only but is still the startup disk. Every other read-only mount is a
    /// disk image or write-locked media: its usage cannot change, so a storage meter has nothing to report.
    public static func isUserStorage(path: String, isLocal: Bool, isReadOnly: Bool) -> Bool {
        guard isLocal else { return false }
        if path == "/" { return true }
        // APFS support volumes, simulator images and hidden mounts are not user storage.
        guard path.hasPrefix("/Volumes/") else { return false }
        return !isReadOnly
    }
}

public struct BatteryReading {
    public let fraction: Double
    public let charging: Bool
    public let onAC: Bool
    public init(fraction: Double, charging: Bool, onAC: Bool) {
        self.fraction = fraction; self.charging = charging; self.onAC = onAC
    }
}

public struct SystemSnapshot {
    public var cpu: Double?
    public var memoryUsed: UInt64?
    public var memoryTotal: UInt64
    public var battery: BatteryReading?
    public var volumes: [StorageVolume]
    public var sampledAt: Date
    public var memoryFraction: Double? {
        guard let used = memoryUsed, memoryTotal > 0 else { return nil }
        return min(1, Double(used) / Double(memoryTotal))
    }
    public init(cpu: Double? = nil, memoryUsed: UInt64? = nil, memoryTotal: UInt64 = 0,
                battery: BatteryReading? = nil, volumes: [StorageVolume] = [], sampledAt: Date = .now) {
        self.cpu = cpu; self.memoryUsed = memoryUsed; self.memoryTotal = memoryTotal
        self.battery = battery; self.volumes = volumes; self.sampledAt = sampledAt
    }
}

public enum MetricSelection {
    public static let defaults = ["cpu", "memory"]
    public static func visible(selected: [String], available: Set<String>) -> [String] {
        var seen = Set<String>()
        return selected.filter { available.contains($0) && seen.insert($0).inserted }
    }
}

public enum ReadingFormat {
    public static func percent(_ value: Double?) -> String {
        guard let value else { return "—" }
        return "\(Int((min(1, max(0, value)) * 100).rounded()))%"
    }
    public static func bytes(_ value: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: value, countStyle: .decimal)
    }
    public static func memory(_ used: UInt64?, total: UInt64) -> String {
        guard let used, total > 0 else { return "Reading…" }
        let gib = 1_073_741_824.0
        return String(format: "%.1f / %.0f GB", Double(used) / gib, Double(total) / gib)
    }
}

/// A dead client or stale heartbeat must end a privileged sleep session.
public enum LeasePolicy {
    public static func shouldEnd(now: TimeInterval, lastHeartbeat: TimeInterval, parentAlive: Bool,
                                 deadline: TimeInterval?, battery: BatteryReading?) -> Bool {
        if !parentAlive || now - lastHeartbeat > 15 { return true }
        if let deadline, now >= deadline { return true }
        if let battery, !battery.onAC && battery.fraction <= 0.1 { return true }
        return false
    }
}
