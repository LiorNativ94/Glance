import Foundation
import CoreFoundation
import CryptoKit

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
        URL(string: self == .claude ? "https://claude.ai/settings/usage" : "https://chatgpt.com/codex/cloud/settings/analytics#usage")!
    }
}

public struct UsageWindow: Identifiable, Equatable, Codable, Sendable {
    public let id: String
    public let title: String
    public let usedPercent: Double
    public let resetsAt: Date?
    public let durationSeconds: TimeInterval?
    public let isGeneral: Bool
    public var remainingFraction: Double { (100 - usedPercent) / 100 }

    public init(id: String, title: String, usedPercent: Double, resetsAt: Date?,
                durationSeconds: TimeInterval? = nil, isGeneral: Bool = true) {
        self.id = id; self.title = title
        self.usedPercent = min(100, max(0, usedPercent.isFinite ? usedPercent : 0))
        self.resetsAt = resetsAt
        self.durationSeconds = durationSeconds
        self.isGeneral = isGeneral
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
    /// A hash of provider-reported identity; never an access-token fingerprint.
    public let accountID: String?
    public let email: String?

    public init(plan: String?, windows: [UsageWindow], updatedAt: Date = .now,
                accountID: String? = nil, email: String? = nil) {
        self.plan = plan; self.windows = windows; self.updatedAt = updatedAt
        self.accountID = accountID; self.email = email
    }

    public func limitingWindow(now: Date = .now) -> UsageWindow? {
        let generalWindows = windows.filter(\.isGeneral)
        guard now.timeIntervalSince(updatedAt) < 600,
              !generalWindows.contains(where: { ($0.resetsAt ?? .distantFuture) <= now }) else { return nil }
        return generalWindows.min { $0.remainingFraction < $1.remainingFraction }
    }

    /// The named window under the same freshness rules as `limitingWindow`; nil picks the limiting window.
    public func window(_ id: String?, now: Date = .now) -> UsageWindow? {
        guard let limiting = limitingWindow(now: now) else { return nil }
        guard let id else { return limiting }
        return windows.first { $0.id == id }
    }

    /// Only numeric limits reported by the provider become meters; missing limits are never zero usage.
    public static func parse(_ data: Data, provider: SubscriptionProvider, plan: String? = nil,
                             now: Date = .now, accountID: String? = nil, email: String? = nil) throws -> SubscriptionUsage {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw SubscriptionError.invalidResponse
        }
        var windows: [UsageWindow] = []
        switch provider {
        case .claude:
            guard root.keys.contains("five_hour") || root.keys.contains("seven_day") || root.keys.contains("limits") else {
                throw SubscriptionError.invalidResponse
            }
            for (key, title) in [("five_hour", "5-hour"), ("seven_day", "Weekly"),
                                  ("seven_day_sonnet", "Sonnet weekly"), ("seven_day_opus", "Opus weekly"),
                                  ("seven_day_oauth_apps", "OAuth apps weekly")] {
                guard let window = root[key] as? [String: Any], let used = number(window["utilization"]) else { continue }
                windows.append(UsageWindow(id: key, title: title, usedPercent: used,
                    resetsAt: (window["resets_at"] as? String).flatMap(parseDate),
                    durationSeconds: key == "five_hour" ? 18_000 : 604_800,
                    isGeneral: key == "five_hour" || key == "seven_day"))
            }
            for key in ["seven_day_routines", "seven_day_claude_routines", "claude_routines", "routines", "routine", "seven_day_cowork", "cowork"] {
                guard let window = root[key] as? [String: Any], let used = number(window["utilization"]) else { continue }
                windows.append(UsageWindow(id: "seven_day_routines", title: "Routines / Cowork weekly", usedPercent: used,
                    resetsAt: (window["resets_at"] as? String).flatMap(parseDate), durationSeconds: 604_800, isGeneral: false))
                break
            }
            var scopedIDs = Set<String>()
            for value in root["limits"] as? [Any] ?? [] {
                guard let entry = value as? [String: Any], entry["kind"] as? String == "weekly_scoped", entry["group"] as? String == "weekly",
                      let percent = number(entry["percent"]),
                      let scope = entry["scope"] as? [String: Any], let model = scope["model"] as? [String: Any],
                      let name = nonEmpty(model["display_name"]) else { continue }
                let modelID = nonEmpty(model["id"]) ?? name
                let normalized = modelID.lowercased().replacingOccurrences(of: "_", with: "-")
                guard name.lowercased() != "all models", normalized != "all-models", !normalized.hasSuffix("-all-models"),
                      scopedIDs.insert(normalized).inserted else { continue }
                // New scoped entries supersede the legacy meter for the same named model.
                if name.lowercased() == "sonnet" || name.lowercased() == "opus" {
                    windows.removeAll { $0.id == "seven_day_" + name.lowercased() }
                }
                windows.append(UsageWindow(id: "claude-scoped-" + normalized, title: name + " weekly", usedPercent: percent,
                    resetsAt: (entry["resets_at"] as? String).flatMap(parseDate), durationSeconds: 604_800, isGeneral: false))
            }
        case .codex:
            guard root.keys.contains("rate_limit") else { throw SubscriptionError.invalidResponse }
            func appendWindows(_ limits: [String: Any], prefix: String = "", name: String? = nil) {
                for (key, fallback) in [("primary_window", "Session"), ("secondary_window", "Weekly")] {
                    guard let window = limits[key] as? [String: Any], let used = number(window["used_percent"]) else { continue }
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
                    windows.append(UsageWindow(id: prefix + key, title: name.map { $0 + " · " + title } ?? title,
                        usedPercent: used, resetsAt: reset, durationSeconds: seconds, isGeneral: name == nil))
                }
            }
            if let limits = root["rate_limit"] as? [String: Any] { appendWindows(limits) }
            var extraIDs = Set<String>()
            for entry in root["additional_rate_limits"] as? [Any] ?? [] {
                guard let entry = entry as? [String: Any],
                      let name = nonEmpty(entry["limit_name"]) ?? nonEmpty(entry["metered_feature"]),
                      let limits = entry["rate_limit"] as? [String: Any] else { continue }
                let id = nonEmpty(entry["metered_feature"]) ?? name
                guard extraIDs.insert(id).inserted else { continue }
                appendWindows(limits, prefix: "codex-extra-" + id + "-", name: name)
            }
        }
        let identity = provider == .codex
            ? (nonEmpty(root["account_id"]) ?? nonEmpty(root["accountId"])).map { SubscriptionIdentity.hash(provider: .codex, components: [$0]) } ?? accountID
            : accountID
        return SubscriptionUsage(plan: (root["plan_type"] as? String) ?? plan, windows: windows, updatedAt: now,
                                 accountID: identity, email: email)
    }

    private static func nonEmpty(_ value: Any?) -> String? {
        guard let text = value as? String else { return nil }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
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

public enum SubscriptionIdentity {
    public static func codexAccount(_ raw: String) -> String {
        hash(provider: .codex, components: [raw.trimmingCharacters(in: .whitespacesAndNewlines)])
    }

    public static func hash(provider: SubscriptionProvider, components: [String]) -> String {
        // Length delimiters avoid ambiguous concatenation; credentials are never inputs.
        let value = provider.rawValue + components.map { "\($0.utf8.count):\($0)" }.joined()
        return SHA256.hash(data: Data(value.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    public static func parseClaudeProfile(_ data: Data) throws -> (accountID: String?, email: String?) {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw SubscriptionError.invalidResponse
        }
        func text(_ object: [String: Any], _ keys: [String]) -> String? {
            keys.compactMap { object[$0] as? String }.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .first { !$0.isEmpty }
        }
        let account = root["account"] as? [String: Any] ?? [:]
        let organization = root["organization"] as? [String: Any] ?? [:]
        let email = text(account, ["emailAddress", "email_address", "email"])
            ?? text(root, ["emailAddress", "email_address", "email"])
        let org = text(organization, ["uuid"]) ?? text(root, ["organizationUuid", "organization_uuid"])
        let user = text(account, ["uuid", "id"]) ?? email?.lowercased()
        guard let org, let user else { return (nil, email) }
        return (hash(provider: .claude, components: [org, user]), email)
    }
}

public struct ResetCredit: Identifiable, Equatable, Sendable {
    public let id: String
    public let resetType: String
    public let status: String
    public let expiresAt: Date?
    public let title: String?

    public init(id: String, resetType: String = "codex_rate_limits", status: String = "available",
                expiresAt: Date? = nil, title: String? = nil) {
        self.id = id; self.resetType = resetType; self.status = status
        self.expiresAt = expiresAt; self.title = title
    }
}

public struct ResetCreditInventory: Equatable, Sendable {
    public let credits: [ResetCredit]
    public let updatedAt: Date
    public init(credits: [ResetCredit], updatedAt: Date = .now) {
        self.credits = credits; self.updatedAt = updatedAt
    }
    public func availableCredits(now: Date = .now) -> [ResetCredit] {
        credits.filter { $0.resetType == "codex_rate_limits" && $0.status == "available" && ($0.expiresAt ?? .distantFuture) > now }
            .sorted { ($0.expiresAt ?? .distantFuture, $0.id) < ($1.expiresAt ?? .distantFuture, $1.id) }
    }
    public func count(now: Date = .now) -> Int { availableCredits(now: now).count }

    public static func parse(_ data: Data, now: Date = .now) throws -> Self {
        struct Payload: Decodable {
            struct Credit: Decodable {
                let id: String
                let reset_type: String
                let status: String
                let expires_at: String?
                let title: String?
            }
            let available_count: Int
            let credits: [Credit]
        }
        let payload = try JSONDecoder().decode(Payload.self, from: data)
        guard payload.available_count >= 0 else { throw SubscriptionError.invalidResponse }
        var ids = Set<String>()
        let credits = try payload.credits.compactMap { credit -> ResetCredit? in
            guard ids.insert(credit.id).inserted else { return nil }
            let date: Date?
            if let raw = credit.expires_at {
                let formatter = ISO8601DateFormatter()
                formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                guard let parsed = formatter.date(from: raw) ?? ISO8601DateFormatter().date(from: raw) else {
                    throw SubscriptionError.invalidResponse
                }
                date = parsed
            } else { date = nil }
            return ResetCredit(id: credit.id, resetType: credit.reset_type, status: credit.status, expiresAt: date, title: credit.title)
        }
        return Self(credits: credits, updatedAt: now)
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
