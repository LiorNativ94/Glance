import Foundation
import CoreFoundation

public enum SubscriptionProvider: String, CaseIterable, Identifiable, Sendable {
    case claude, codex
    public var id: String { rawValue }
    public var name: String { rawValue.capitalized }
    public var signInHelp: String {
        switch self {
        case .claude: return "Sign in with Claude Code, then click Refresh."
        case .codex: return "Run codex login with your ChatGPT account, then click Refresh."
        }
    }
    public var usageURL: URL {
        URL(string: self == .claude ? "https://claude.ai/settings/usage" : "https://chatgpt.com/codex/settings/usage")!
    }
}

public struct UsageWindow: Identifiable, Equatable, Sendable {
    public let id: String
    public let title: String
    public let usedPercent: Double
    public let resetsAt: Date?
    public var remainingFraction: Double { (100 - usedPercent) / 100 }

    public init(id: String, title: String, usedPercent: Double, resetsAt: Date?) {
        self.id = id; self.title = title
        self.usedPercent = min(100, max(0, usedPercent.isFinite ? usedPercent : 0))
        self.resetsAt = resetsAt
    }

    public func resetDescription(now: Date = .now) -> String {
        guard let resetsAt else { return "Reset time unavailable" }
        let seconds = resetsAt.timeIntervalSince(now)
        guard seconds > 0 else { return "Reset due · refresh to update" }
        let minutes = Int(ceil(min(seconds, 315_360_000) / 60))
        if minutes < 60 { return "Resets in \(minutes)m" }
        let hours = minutes / 60
        if hours < 24 { return "Resets in \(hours)h \(minutes % 60)m" }
        return "Resets in \(hours / 24)d \(hours % 24)h"
    }
}

public struct SubscriptionUsage: Equatable, Sendable {
    public let plan: String?
    public let windows: [UsageWindow]
    public let updatedAt: Date

    public init(plan: String?, windows: [UsageWindow], updatedAt: Date = .now) {
        self.plan = plan; self.windows = windows; self.updatedAt = updatedAt
    }

    public func limitingWindow(now: Date = .now) -> UsageWindow? {
        guard now.timeIntervalSince(updatedAt) < 600,
              !windows.contains(where: { ($0.resetsAt ?? .distantFuture) <= now }) else { return nil }
        return windows.min { $0.remainingFraction < $1.remainingFraction }
    }

    /// Only numeric limits reported by the provider become meters; missing limits are never zero usage.
    public static func parse(_ data: Data, provider: SubscriptionProvider, plan: String? = nil,
                             now: Date = .now) throws -> SubscriptionUsage {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw SubscriptionError.invalidResponse
        }
        var windows: [UsageWindow] = []
        switch provider {
        case .claude:
            guard root.keys.contains("five_hour") || root.keys.contains("seven_day") else {
                throw SubscriptionError.invalidResponse
            }
            for (key, title) in [("five_hour", "5-hour"), ("seven_day", "Weekly"),
                                  ("seven_day_sonnet", "Sonnet weekly"), ("seven_day_opus", "Opus weekly")] {
                guard let window = root[key] as? [String: Any],
                      let used = number(window["utilization"]) else { continue }
                let reset = (window["resets_at"] as? String).flatMap(parseDate)
                windows.append(UsageWindow(id: key, title: title, usedPercent: used, resetsAt: reset))
            }
        case .codex:
            guard root.keys.contains("rate_limit") else { throw SubscriptionError.invalidResponse }
            if let limits = root["rate_limit"] as? [String: Any] {
                for (key, fallback) in [("primary_window", "Session"), ("secondary_window", "Weekly")] {
                    guard let window = limits[key] as? [String: Any],
                          let used = number(window["used_percent"]) else { continue }
                    let seconds = number(window["limit_window_seconds"])
                    let title: String
                    switch seconds {
                    case 18_000: title = "5-hour"
                    case 604_800: title = "Weekly"
                    case .some(let duration) where duration > 0 && duration < 604_800:
                        title = "\(Int(ceil(duration / 3600)))-hour"
                    default: title = fallback
                    }
                    let reset = number(window["reset_at"]).flatMap { value -> Date? in
                        guard value > 0, value < 253_402_300_800 else { return nil }
                        return Date(timeIntervalSince1970: value)
                    }
                    windows.append(UsageWindow(id: key, title: title, usedPercent: used, resetsAt: reset))
                }
            }
        }
        return SubscriptionUsage(plan: (root["plan_type"] as? String) ?? plan, windows: windows, updatedAt: now)
    }

    private static func number(_ value: Any?) -> Double? {
        guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID(),
              number.doubleValue.isFinite else { return nil }
        return number.doubleValue
    }
    private static func parseDate(_ text: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: text) ?? ISO8601DateFormatter().date(from: text)
    }
}

public enum SubscriptionError: Error, LocalizedError {
    case signIn(SubscriptionProvider)
    case keychain
    case invalidResponse
    case rateLimited(Date)
    case server(Int)

    public var errorDescription: String? {
        switch self {
        case .signIn(let provider): return provider.signInHelp
        case .keychain: return "Allow Keychain access by clicking Refresh to use your existing sign-in."
        case .invalidResponse: return "The provider did not return a supported usage reading."
        case .rateLimited: return "Too many requests. Glance will retry after the provider’s cooldown."
        case .server(let status): return "Usage is unavailable (HTTP \(status)). Try again later."
        }
    }
}
