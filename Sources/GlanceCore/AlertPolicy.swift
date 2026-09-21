import Foundation

public enum AlertKind: String, CaseIterable, Identifiable {
    case ai, codexSessions, memory, storage
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .ai: return "AI allowance"
        case .codexSessions: return "Codex sessions"
        case .memory: return "Memory pressure"
        case .storage: return "Low disk space"
        }
    }
}

public struct AlertThresholds: Equatable {
    public let aiRemainingPercent: Int
    public let storageFreePercent: Int
    public let storageFreeGB: Int
    public init(aiRemainingPercent: Int = 20, storageFreePercent: Int = 5, storageFreeGB: Int = 10) {
        self.aiRemainingPercent = min(100, max(1, aiRemainingPercent))
        self.storageFreePercent = min(100, max(1, storageFreePercent))
        self.storageFreeGB = min(1000, max(1, storageFreeGB))
    }
}

public struct GlanceAlert: Equatable {
    public let id: String
    public let kind: AlertKind
    public let title: String
    public let body: String
    public let destination: String?
    public init(id: String, kind: AlertKind, title: String, body: String, destination: String? = nil) {
        self.id = id; self.kind = kind; self.title = title; self.body = body; self.destination = destination
    }
}

/// Remember each episode so repeated samples do not produce repeated notifications.
public struct AlertPolicy {
    private var reported: [String: String] = [:]
    private var pressureSince: Date?
    public init() {}

    public mutating func evaluate(enabled: Set<AlertKind>, snapshot: SystemSnapshot,
                                  memoryPressure: Bool, usages: [SubscriptionProvider: SubscriptionUsage],
                                  thresholds: AlertThresholds = AlertThresholds(),
                                  now: Date = .now) -> [GlanceAlert] {
        var alerts: [GlanceAlert] = []
        for kind in AlertKind.allCases where !enabled.contains(kind) {
            reported = reported.filter { !$0.key.hasPrefix(kind.rawValue + ":") }
        }
        if enabled.contains(.memory), memoryPressure {
            if pressureSince == nil { pressureSince = now }
            if now.timeIntervalSince(pressureSince!) >= 60, reported["memory:pressure"] == nil {
                reported["memory:pressure"] = "active"
                alerts.append(GlanceAlert(id: "memory:pressure", kind: .memory, title: "Memory pressure is elevated",
                                          body: "macOS has reported elevated memory pressure for one minute. Open Glance to review memory use."))
            }
        } else {
            pressureSince = nil
            reported.removeValue(forKey: "memory:pressure")
        }
        if enabled.contains(.storage) {
            // Keep disconnected volumes latched until a real reading confirms recovery.
            for volume in snapshot.volumes {
                let key = "storage:" + volume.id
                let low = volume.total > 0 && Double(volume.available) / Double(volume.total) < Double(thresholds.storageFreePercent) / 100
                    && volume.available < Int64(thresholds.storageFreeGB) * 1_000_000_000
                if !low { reported.removeValue(forKey: key) }
                else if reported[key] == nil {
                    reported[key] = "active"
                    alerts.append(GlanceAlert(id: key, kind: .storage, title: "\(volume.name) is running low",
                                              body: "\(ReadingFormat.bytes(volume.available)) free. Open Glance to review storage."))
                }
            }
        }
        if enabled.contains(.ai) {
            for provider in SubscriptionProvider.allCases {
                guard let usage = usages[provider], let window = usage.limitingWindow(now: now) else { continue }
                let prefix = "ai:" + provider.rawValue + ":"
                for recovered in usage.windows where recovered.remainingFraction > Double(thresholds.aiRemainingPercent) / 100 {
                    reported.removeValue(forKey: prefix + recovered.id)
                }
                let key = prefix + window.id
                let episode = window.resetsAt.map { String($0.timeIntervalSince1970) } ?? "unknown"
                if window.remainingFraction <= Double(thresholds.aiRemainingPercent) / 100, reported[key] != episode {
                    reported[key] = episode
                    alerts.append(GlanceAlert(id: key, kind: .ai, title: "\(provider.name) allowance is low",
                                              body: "\(ReadingFormat.percent(window.remainingFraction)) left · \(window.title) · \(window.resetDescription(now: now))"))
                }
            }
        }
        // Codex session transitions are evaluated by the live session store.
        return alerts
    }

    public mutating func retry(_ alert: GlanceAlert) { reported.removeValue(forKey: alert.id) }
}
