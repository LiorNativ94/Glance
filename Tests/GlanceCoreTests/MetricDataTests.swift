import XCTest
import GlanceCore
@testable import Glance

final class MetricDataTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private func usage(_ used: Double, at date: Date, account: String? = "a", plan: String = "Plus", reset: Date?) -> SubscriptionUsage {
        SubscriptionUsage(plan: plan, windows: [UsageWindow(id: "weekly", title: "Weekly", usedPercent: used, resetsAt: reset)],
                          updatedAt: date, accountID: account)
    }
    func testHistoryPreservesDailyDeltasAndDoesNotInventMissingCoverage() {
        var history = QuotaHistory()
        let reset = now.addingTimeInterval(86400)
        for (seconds, value) in [(0.0, 20.0), (300, 25), (600, 27), (8000, 40), (8300, 43), (8600, 41)] {
            history.record(provider: .codex, usage: usage(value, at: now.addingTimeInterval(seconds), reset: reset))
        }
        let periods = history.periods(provider: .codex, account: "a", window: "weekly")
        XCTAssertEqual(periods.count, 1)
        XCTAssertEqual(periods[0].days().compactMap(\.value).reduce(0, +), 10)
        XCTAssertEqual(periods[0].last.used, 41, "Last observed is not peak utilization")
        XCTAssertTrue(periods[0].days().allSatisfy(\.gaps))
    }
    func testHistoryIsolatesResetJitterAccountsAndPlanEpochsIncludingMissingWindows() {
        var history = QuotaHistory()
        let reset = now.addingTimeInterval(86400)
        history.record(provider: .codex, usage: usage(30, at: now, reset: reset))
        history.record(provider: .codex, usage: usage(32, at: now.addingTimeInterval(300), reset: reset.addingTimeInterval(60)))
        XCTAssertEqual(history.periods(provider: .codex, account: "a", window: "weekly").count, 1)
        history.record(provider: .codex, usage: usage(5, at: now.addingTimeInterval(600), plan: "Pro", reset: nil))
        XCTAssertTrue(history.periods(provider: .codex, account: "a", window: "weekly").isEmpty)
        history.record(provider: .codex, usage: usage(9, at: now.addingTimeInterval(900), reset: reset))
        XCTAssertEqual(history.periods(provider: .codex, account: "a", window: "weekly").first?.observations.count, 1)
        XCTAssertTrue(history.periods(provider: .codex, account: "b", window: "weekly").isEmpty)
        XCTAssertTrue(history.periods(provider: .claude, account: "a", window: "weekly").isEmpty)
        history.record(provider: .codex, usage: usage(90, at: now.addingTimeInterval(1200), account: nil, reset: reset))
        XCTAssertEqual(history.observations.count, 3)
    }
    func testHistorySeparatesCyclesAndPrunesOldRecords() throws {
        var history = QuotaHistory()
        history.record(provider: .claude, usage: usage(98, at: now, reset: now.addingTimeInterval(100)))
        history.record(provider: .claude, usage: usage(2, at: now.addingTimeInterval(300), reset: now.addingTimeInterval(604800)))
        let periods = history.periods(provider: .claude, account: "a", window: "weekly")
        XCTAssertEqual(periods.count, 2)
        XCTAssertNil(periods[0].days()[0].value)
        XCTAssertEqual(periods[1].last.used, 98)
        history = try JSONDecoder().decode(QuotaHistory.self, from: JSONEncoder().encode(history))
        history.prune(now: now.addingTimeInterval(91 * 86400))
        XCTAssertTrue(history.observations.isEmpty)
    }
    func testProcessCPUUsesMonotonicIntervalAndNativeReadings() throws {
        XCTAssertEqual(ProcessReader.cpuPercent(current: 3_000_000_000, previous: 1_000_000_000, elapsed: 1), 200)
        XCTAssertNil(ProcessReader.cpuPercent(current: 1, previous: 2, elapsed: 1))
        XCTAssertNil(ProcessReader.cpuPercent(current: 2, previous: 1, elapsed: 0))
        let reader = ProcessReader()
        let first = reader.read()
        let own = try XCTUnwrap(first.processes.first { $0.pid == getpid() })
        XCTAssertNil(own.cpuPercent)
        XCTAssertGreaterThan(own.residentBytes, 0)
        let second = try XCTUnwrap(reader.read().processes.first { $0.pid == getpid() })
        XCTAssertEqual(second.id, own.id)
        XCTAssertNotNil(second.cpuPercent)
        XCTAssertNotNil(first.swapBytes)
        XCTAssertNotNil(first.compressedBytes)
    }
    func testProcessCPUAgreesWithOSAccountingDuringARealWorkload() throws {
        let reader = ProcessReader()
        _ = reader.read()
        var before = rusage(); getrusage(RUSAGE_SELF, &before)
        let start = ProcessInfo.processInfo.systemUptime
        var iterations = 0
        while ProcessInfo.processInfo.systemUptime - start < 0.4 { iterations &+= 1 }
        var after = rusage(); getrusage(RUSAGE_SELF, &after)
        let elapsed = ProcessInfo.processInfo.systemUptime - start
        let measured = try XCTUnwrap(reader.read().processes.first { $0.pid == getpid() }?.cpuPercent)
        func seconds(_ usage: rusage) -> Double {
            Double(usage.ru_utime.tv_sec + usage.ru_stime.tv_sec) + Double(usage.ru_utime.tv_usec + usage.ru_stime.tv_usec) / 1_000_000
        }
        let expected = (seconds(after) - seconds(before)) / elapsed * 100
        XCTAssertGreaterThan(iterations, 0)
        XCTAssertEqual(measured, expected, accuracy: 15, "Native process counters use mach time units; convert with the platform timebase")
    }
    func testScopedLimitsDoNotBecomeGeneralQuotaAndMalformedSiblingsAreIgnored() throws {
        let payload = Data("""
        {"five_hour":{"utilization":20},"seven_day_sonnet":{"utilization":35},"limits":[null,
        {"kind":"weekly_scoped","group":"weekly","percent":100,"resets_at":"2020-01-01T00:00:00Z","scope":{"model":{"id":"sonnet","display_name":"Sonnet"}}},
        {"kind":"weekly_scoped","group":"weekly","percent":100,"scope":{"model":{"id":"sonnet","display_name":"Sonnet"}}}]}
        """.utf8)
        let parsed = try SubscriptionUsage.parse(payload, provider: .claude, now: now)
        XCTAssertEqual(parsed.windows.count, 2)
        XCTAssertEqual(parsed.limitingWindow(now: now)?.usedPercent, 20)
        var policy = AlertPolicy()
        XCTAssertTrue(policy.evaluate(enabled: [.ai], snapshot: .init(), memoryPressure: false, usages: [.claude: parsed], now: now).isEmpty)
        let codex = try SubscriptionUsage.parse(Data("""
        {"account_id":"account-a","rate_limit":{"primary_window":{"used_percent":12}},"additional_rate_limits":[false,
        {"limit_name":"Example model","metered_feature":"example","rate_limit":{"primary_window":{"used_percent":99}}}]}
        """.utf8), provider: .codex, now: now)
        XCTAssertEqual(codex.accountID, SubscriptionIdentity.codexAccount("account-a"))
        XCTAssertEqual(codex.windows.last?.isGeneral, false)
        XCTAssertEqual(codex.limitingWindow(now: now)?.usedPercent, 12)
    }
    func testResetInventoryUsesExpiryAndNeverRedeems() throws {
        let inventory = try ResetCreditInventory.parse(Data("""
        {"available_count":99,"credits":[
        {"id":"expired","reset_type":"codex_rate_limits","status":"available","expires_at":"2020-01-01T00:00:00Z"},
        {"id":"used","reset_type":"codex_rate_limits","status":"redeemed"},
        {"id":"ready","reset_type":"codex_rate_limits","status":"available"}]}
        """.utf8), now: now)
        XCTAssertEqual(inventory.count(now: now), 1)
        let request = SubscriptionClient.resetRequest(credentials: .init(accessToken: "fixture", accountID: "a", plan: nil))
        XCTAssertEqual(request.httpMethod, "GET")
        XCTAssertEqual(request.url?.path, "/backend-api/wham/rate-limit-reset-credits")
    }
    @MainActor func testOptionalResetFailureKeepsFreshAllowance() async throws {
        let suite = "Glance.ResetTests.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(["codex"], forKey: "subscriptionProviders")
        let value = usage(20, at: now, reset: now.addingTimeInterval(86400))
        let store = await MainActor.run {
            SubscriptionStore(defaults: defaults, startPolling: false,
                              resetFetch: { _ in throw SubscriptionError.server(503) }, fetch: { _, _ in value })
        }
        await MainActor.run { store.refresh(.codex) }
        for _ in 0..<100 {
            if await MainActor.run(body: { store.states[.codex]?.resetError != nil }) { break }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        await MainActor.run {
            XCTAssertEqual(store.states[.codex]?.usage, value)
            XCTAssertNil(store.states[.codex]?.error)
            XCTAssertNotNil(store.states[.codex]?.resetError)
        }
    }
}
