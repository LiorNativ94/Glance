import AppKit
import XCTest
import GlanceCore
@testable import Glance

final class SubscriptionTests: XCTestCase {
    private func data(_ json: String) -> Data { Data(json.utf8) }

    func testClaudeWindowsAndMissingValues() throws {
        let usage = try SubscriptionUsage.parse(data("""
        {"five_hour":{"utilization":23.5,"resets_at":"2026-09-14T15:00:00.123Z"},
         "seven_day":{"utilization":81,"resets_at":"2026-09-18T12:00:00Z"},
         "seven_day_sonnet":{"utilization":null},"seven_day_opus":{"utilization":0}}
        """), provider: .claude, plan: "max")
        XCTAssertEqual(usage.plan, "max")
        XCTAssertEqual(usage.windows.map(\.usedPercent), [23.5, 81, 0])
        XCTAssertEqual(usage.windows.map(\.title), ["5-hour", "Weekly", "Opus weekly"])
        XCTAssertNotNil(usage.windows[0].resetsAt)
        XCTAssertNotNil(usage.windows[1].resetsAt)
        XCTAssertNil(usage.windows[2].resetsAt)
    }

    func testCodexUsesReportedDurationAndClampsPercentages() throws {
        let usage = try SubscriptionUsage.parse(data("""
        {"plan_type":"pro","rate_limit":{
         "primary_window":{"used_percent":-3,"reset_at":1800000000,"limit_window_seconds":18000},
         "secondary_window":{"used_percent":108,"reset_at":1800100000,"limit_window_seconds":604800}}}
        """), provider: .codex)
        XCTAssertEqual(usage.plan, "pro")
        XCTAssertEqual(usage.windows.map(\.title), ["5-hour", "Weekly"])
        XCTAssertEqual(usage.windows.map(\.usedPercent), [0, 100])
        XCTAssertEqual(usage.windows[1].remainingFraction, 0)
        XCTAssertEqual(usage.windows[0].resetsAt, Date(timeIntervalSince1970: 1800000000))
    }

    func testUnavailableLimitsAreNotZeroUsage() throws {
        for (provider, json) in [(SubscriptionProvider.codex, "{\"rate_limit\":null}"),
                                 (.claude, "{\"five_hour\":null,\"seven_day\":{\"utilization\":true}}") ] {
            XCTAssertTrue(try SubscriptionUsage.parse(data(json), provider: provider).windows.isEmpty)
        }
        XCTAssertThrowsError(try SubscriptionUsage.parse(data("{\"error\":\"unauthorized\"}"), provider: .claude))
        XCTAssertThrowsError(try SubscriptionUsage.parse(data("[]"), provider: .codex))
    }

    func testResetCountdownNeverPromisesAnUnverifiedReset() {
        let now = Date(timeIntervalSince1970: 1800000000)
        let expired = UsageWindow(id: "a", title: "Weekly", usedPercent: 100, resetsAt: now)
        XCTAssertEqual(expired.resetDescription(now: now), "Reset due · refresh to update")
        XCTAssertEqual(expired.remainingFraction, 0)
        let future = UsageWindow(id: "a", title: "Session", usedPercent: 30, resetsAt: now.addingTimeInterval(3660))
        XCTAssertEqual(future.resetDescription(now: now), "Resets in 1h 1m")
    }

    func testSubscriptionCredentialsRejectAPIKeysAndExpiredClaudeTokens() throws {
        XCTAssertThrowsError(try SubscriptionCredentials.parse(data("{\"OPENAI_API_KEY\":\"test-only\"}"), provider: .codex))
        XCTAssertThrowsError(try SubscriptionCredentials.parse(data("{\"mcpOAuth\":{}}"), provider: .claude))
        XCTAssertThrowsError(try SubscriptionCredentials.parse(data("""
        {"claudeAiOauth":{"accessToken":"test-only","expiresAt":1,"scopes":["user:profile"]}}
        """), provider: .claude))
        XCTAssertThrowsError(try SubscriptionCredentials.parse(data("""
        {"claudeAiOauth":{"accessToken":"test-only","scopes":["user:inference"]}}
        """), provider: .claude))
        let credentials = try SubscriptionCredentials.parse(data("""
        {"tokens":{"access_token":"test-only","account_id":"test-account"}}
        """), provider: .codex)
        XCTAssertEqual(credentials.accountID, "test-account")
    }

    func testRequestsUseOnlyProviderEndpointsAndAccountScope() {
        let credentials = SubscriptionCredentials(accessToken: "test-only", accountID: "test-account", plan: nil)
        let codex = SubscriptionClient.request(.codex, credentials: credentials)
        XCTAssertEqual(codex.url?.absoluteString, "https://chatgpt.com/backend-api/wham/usage")
        XCTAssertEqual(codex.value(forHTTPHeaderField: "ChatGPT-Account-Id"), "test-account")
        XCTAssertEqual(codex.value(forHTTPHeaderField: "Authorization"), "Bearer test-only")
        let claude = SubscriptionClient.request(.claude, credentials: credentials)
        XCTAssertEqual(claude.url?.absoluteString, "https://api.anthropic.com/api/oauth/usage")
        XCTAssertEqual(claude.value(forHTTPHeaderField: "anthropic-beta"), "oauth-2025-04-20")
        XCTAssertNil(claude.value(forHTTPHeaderField: "ChatGPT-Account-Id"))
    }

    func testHTTPFailuresAndRetryAfter() throws {
        let now = Date(timeIntervalSince1970: 1800000000)
        for code in [401, 403, 429, 500, 302] {
            let response = try XCTUnwrap(HTTPURLResponse(url: URL(string: "https://api.anthropic.com")!, statusCode: code,
                                                       httpVersion: nil, headerFields: ["Retry-After": "900"]))
            XCTAssertThrowsError(try SubscriptionClient.validate(response, provider: .claude, now: now)) { error in
                if code == 429 {
                    guard case SubscriptionError.rateLimited(let date) = error else { return XCTFail("Expected cooldown") }
                    XCTAssertEqual(date.timeIntervalSince(now), 900)
                }
            }
        }
    }

    @MainActor func testDisconnectDiscardsInFlightReadingsAndPersistsChoice() async throws {
        let suite = "Glance.SubscriptionTests.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        var continuation: CheckedContinuation<SubscriptionUsage, Error>?
        let started = expectation(description: "fetch started")
        let store = SubscriptionStore(defaults: defaults, startPolling: false, fetch: { _, interactive in
            XCTAssertTrue(interactive)
            return try await withCheckedThrowingContinuation { continuation = $0; started.fulfill() }
        })
        XCTAssertTrue(store.enabled.isEmpty)
        store.setEnabled(.codex, true)
        await fulfillment(of: [started], timeout: 2)
        XCTAssertTrue(store.states[.codex]?.refreshing == true)
        store.setEnabled(.codex, false)
        continuation?.resume(returning: SubscriptionUsage(plan: "pro", windows: []))
        for _ in 0..<10 { await Task.yield() }
        XCTAssertNil(store.states[.codex])
        XCTAssertTrue(SubscriptionStore(defaults: defaults, startPolling: false).enabled.isEmpty)
    }

    @MainActor func testRefreshCooldownAndNoDuplicateFetches() async throws {
        let suite = "Glance.SubscriptionTests.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        var calls = 0
        let store = SubscriptionStore(defaults: defaults, startPolling: false, fetch: { _, _ in
            calls += 1
            throw SubscriptionError.rateLimited(Date().addingTimeInterval(900))
        })
        store.setEnabled(.claude, true)
        store.refresh(.claude)
        for _ in 0..<10 { await Task.yield() }
        store.refresh(.claude, allowInteraction: true)
        for _ in 0..<10 { await Task.yield() }
        XCTAssertEqual(calls, 1)
        XCTAssertNotNil(store.states[.claude]?.error)
        XCTAssertNil(store.remaining(.claude))
    }

    func testNotchHeaderStaysInsideMenuBarAndLeavesCameraGap() {
        for screen in [NSRect(x: 0, y: 0, width: 1512, height: 982),
                       NSRect(x: -1920, y: 300, width: 1920, height: 1080)] {
            let left = NSRect(x: screen.minX, y: screen.maxY - 32, width: screen.width / 2 - 90, height: 32)
            let right = NSRect(x: screen.midX + 90, y: screen.maxY - 32, width: screen.width / 2 - 90, height: 32)
            let frame = NotchController.headerFrame(screen: screen, safeAreaTop: 32, menuBarHeight: 33,
                                                   leftArea: left, rightArea: right, leftWidth: 56, rightWidth: 56)
            XCTAssertEqual(frame.midX, screen.midX)
            XCTAssertEqual(frame.maxY, screen.maxY)
            XCTAssertEqual(frame.minY, screen.maxY - 32)
            XCTAssertEqual(frame.width - 112, 180)
            XCTAssertTrue(screen.contains(frame))
            let plain = NotchController.headerFrame(screen: screen, safeAreaTop: 0, menuBarHeight: 24,
                                                   leftArea: nil, rightArea: nil, leftWidth: 56, rightWidth: 56)
            XCTAssertEqual(plain.height, 24)
            XCTAssertEqual(plain.maxY, screen.maxY)
            XCTAssertEqual(plain.width, 112)
        }
    }

    func testPaceProjectsCurrentRateAgainstReset() {
        let now = Date()
        func window(used: Double, resetsIn: TimeInterval, duration: TimeInterval? = 18_000) -> UsageWindow {
            UsageWindow(id: "five_hour", title: "5-hour", usedPercent: used, resetsAt: now.addingTimeInterval(resetsIn), durationSeconds: duration)
        }
        let fast = window(used: 50, resetsIn: 14_400).pace(now: now)
        XCTAssertEqual(fast?.text, "At this pace, runs out in 1h 0m")
        XCTAssertEqual(fast?.runsOutEarly, true)
        XCTAssertEqual(window(used: 10, resetsIn: 14_400).pace(now: now)?.runsOutEarly, false)
        XCTAssertEqual(window(used: 0, resetsIn: 14_400).pace(now: now)?.text, "On pace to last until reset")
        XCTAssertNil(window(used: 40, resetsIn: 17_700).pace(now: now), "Too early in the window to judge")
        XCTAssertNil(window(used: 100, resetsIn: 14_400).pace(now: now))
        XCTAssertNil(window(used: 50, resetsIn: -60).pace(now: now))
        XCTAssertNil(window(used: 50, resetsIn: 14_400, duration: nil).pace(now: now))
    }

    func testExpiredClaudeTokenExplainsRenewal() {
        XCTAssertThrowsError(try SubscriptionCredentials.parse(data("""
        {"claudeAiOauth":{"accessToken":"test-only","expiresAt":1,"scopes":["user:profile"]}}
        """), provider: .claude)) { error in
            guard case SubscriptionError.expired(.claude) = error else { return XCTFail("Expected expiry, got \(error)") }
            XCTAssertTrue(error.localizedDescription.contains("next time you use Claude Code"))
        }
    }

    func testSecurityToolOutputDropsTrailingNewline() {
        XCTAssertEqual(SubscriptionCredentials.trimmingNewlines(data("{\"a\":1}\n")), data("{\"a\":1}"))
        XCTAssertEqual(SubscriptionCredentials.trimmingNewlines(data("{}\r\n")), data("{}"))
    }

    @MainActor func testTemporaryFailureKeepsReadingButSignInFailureClearsIt() async throws {
        let suite = "Glance.SubscriptionTests.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let reading = SubscriptionUsage(plan: "max", windows: [UsageWindow(id: "five_hour", title: "5-hour", usedPercent: 30, resetsAt: nil)])
        var results: [Result<SubscriptionUsage, Error>] = [
            .success(reading), .failure(URLError(.notConnectedToInternet)), .failure(SubscriptionError.expired(.claude)),
            .failure(SubscriptionError.server(503)), .failure(SubscriptionError.signIn(.claude))]
        let store = SubscriptionStore(defaults: defaults, startPolling: false, fetch: { _, _ in try results.removeFirst().get() })
        func refresh() async {
            store.refresh(.claude)
            for _ in 0..<10 { await Task.yield() }
        }
        store.setEnabled(.claude, true)
        for _ in 0..<10 { await Task.yield() }
        XCTAssertEqual(store.states[.claude]?.usage, reading)
        for _ in 0..<3 {
            await refresh()
            XCTAssertEqual(store.states[.claude]?.usage, reading)
            XCTAssertNotNil(store.states[.claude]?.error)
            XCTAssertEqual(store.states[.claude]?.refreshing, false)
        }
        await refresh()
        XCTAssertNil(store.states[.claude]?.usage)
        XCTAssertEqual(store.states[.claude]?.error, SubscriptionProvider.claude.signInHelp)
    }

    func testNamedWindowFollowsLimitingWindowFreshness() {
        let now = Date()
        let windows = [UsageWindow(id: "five_hour", title: "5-hour", usedPercent: 10, resetsAt: now.addingTimeInterval(3_600)),
                       UsageWindow(id: "seven_day", title: "Weekly", usedPercent: 70, resetsAt: now.addingTimeInterval(86_400))]
        let usage = SubscriptionUsage(plan: "Max", windows: windows, updatedAt: now)

        XCTAssertEqual(usage.window(nil, now: now)?.id, "seven_day")
        XCTAssertEqual(usage.window("five_hour", now: now)?.remainingFraction, 0.9)
        XCTAssertEqual(usage.window("seven_day", now: now)?.remainingFraction, 0.3)
        XCTAssertNil(usage.window("five_hour", now: now.addingTimeInterval(601)))
    }
}
