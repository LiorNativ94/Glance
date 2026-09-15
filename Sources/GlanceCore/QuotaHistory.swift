import Foundation

/// Samples are observations, never a claim of complete billing or quota accounting.
public struct QuotaObservation: Codable, Identifiable, Equatable {
    public let id: UUID
    public let provider: String
    public let account: String
    public let plan: String
    public let epoch: UUID
    public let window: String
    public let title: String
    public let date: Date
    public let reset: Date
    public let used: Double
}

public struct QuotaDay: Identifiable {
    public let date: Date
    public var observed: Double = 0
    public var intervals: Int = 0
    public var gaps: Bool = false
    public var id: Date { date }
    public var value: Double? { intervals > 0 ? observed : nil }
}

public struct QuotaPeriod: Identifiable {
    public let observations: [QuotaObservation]
    public var id: UUID { observations[0].id }
    public var reset: Date { observations[0].reset }
    public var last: QuotaObservation { observations.last! }
    public var first: QuotaObservation { observations[0] }
    public var isComplete: Bool { reset <= .now }

    public func days(calendar: Calendar = .current) -> [QuotaDay] {
        var results: [Date: QuotaDay] = [:]
        for sample in observations {
            let day = calendar.startOfDay(for: sample.date)
            if results[day] == nil { results[day] = QuotaDay(date: day, gaps: true) }
        }
        for (a, b) in zip(observations, observations.dropFirst()) {
            let day = calendar.startOfDay(for: b.date)
            // Missing intervals, midnight, counter corrections, and sleep are unknown, not zero.
            guard b.date.timeIntervalSince(a.date) <= 660, b.date > a.date,
                  calendar.isDate(a.date, inSameDayAs: b.date), b.used >= a.used else {
                results[day, default: QuotaDay(date: day)].gaps = true
                continue
            }
            results[day, default: QuotaDay(date: day)].observed += b.used - a.used
            results[day, default: QuotaDay(date: day)].intervals += 1
        }
        guard let start = results.keys.min(), let end = results.keys.max() else { return [] }
        var cursor = start
        while cursor <= end {
            if results[cursor] == nil { results[cursor] = QuotaDay(date: cursor, gaps: true) }
            guard let next = calendar.date(byAdding: .day, value: 1, to: cursor), next > cursor else { break }
            cursor = next
        }
        return results.values.sorted { $0.date < $1.date }
    }
}

public struct QuotaHistory: Codable {
    private struct Scope: Codable { let plan: String; let epoch: UUID }
    private var scopes: [String: Scope] = [:]
    public private(set) var observations: [QuotaObservation] = []
    public init() {}

    public mutating func record(provider: SubscriptionProvider, usage: SubscriptionUsage) {
        guard let account = usage.accountID, !account.isEmpty else { return }
        let plan = usage.plan ?? "Unknown plan"
        let key = provider.rawValue + ":" + account
        let scope = scopes[key]
        let epoch = scope?.plan == plan ? scope!.epoch : UUID()
        scopes[key] = Scope(plan: plan, epoch: epoch)
        for window in usage.windows {
            guard let reset = window.resetsAt, reset > usage.updatedAt else { continue }
            let previous = observations.last {
                $0.provider == provider.rawValue && $0.account == account && $0.epoch == epoch && $0.window == window.id
            }
            guard previous == nil || usage.updatedAt > previous!.date else { continue }
            // Providers can jitter the advertised reset slightly without starting a new quota cycle.
            let boundary = previous.flatMap { abs($0.reset.timeIntervalSince(reset)) <= 120 ? $0.reset : nil } ?? reset
            observations.append(QuotaObservation(id: UUID(), provider: provider.rawValue, account: account,
                plan: plan, epoch: epoch, window: window.id, title: window.title,
                date: usage.updatedAt, reset: boundary, used: window.usedPercent))
        }
        prune(now: usage.updatedAt)
    }

    public mutating func prune(now: Date = .now) {
        observations.removeAll { $0.date < now.addingTimeInterval(-90 * 86400) || $0.date > now.addingTimeInterval(60) }
    }

    public func periods(provider: SubscriptionProvider, account: String?, window: String, plan: String? = nil) -> [QuotaPeriod] {
        guard let account else { return [] }
        let samples = observations.filter { $0.provider == provider.rawValue && $0.account == account }
        guard let scope = scopes[provider.rawValue + ":" + account], plan == nil || scope.plan == plan else { return [] }
        let epoch = scope.epoch
        let selected = samples.filter { $0.epoch == epoch && $0.window == window }
        return Dictionary(grouping: selected, by: \.reset).values
            .map { QuotaPeriod(observations: $0.sorted { $0.date < $1.date }) }
            .sorted { $0.reset > $1.reset }
    }
}
