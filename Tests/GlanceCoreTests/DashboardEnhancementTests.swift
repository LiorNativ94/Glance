import XCTest
import GlanceCore
@testable import Glance

final class DashboardEnhancementTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    func testCustomThresholdsPersistAndChangeAIAndStorageTriggers() throws {
        let suite = "Glance.ThresholdTests.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let model = AppModel(defaults: defaults, subscriptions: SubscriptionStore(defaults: defaults, startPolling: false))
        XCTAssertEqual(model.alertThresholds, AlertThresholds())
        model.updateAlertThresholds(ai: 35, storagePercent: 20, storageGB: 50)
        let restored = AppModel(defaults: defaults, subscriptions: SubscriptionStore(defaults: defaults, startPolling: false))
        XCTAssertEqual(restored.alertThresholds, AlertThresholds(aiRemainingPercent: 35, storageFreePercent: 20, storageFreeGB: 50))
        XCTAssertTrue(restored.enabledAlerts.isEmpty, "Editing thresholds must not opt into notifications")
        let usage = SubscriptionUsage(plan: nil, windows: [UsageWindow(id: "weekly", title: "Weekly", usedPercent: 65,
                                                                    resetsAt: now.addingTimeInterval(3600))], updatedAt: now)
        let volume = StorageVolume(id: "internal", name: "Mac", path: "/", total: 250_000_000_000,
                                   available: 30_000_000_000, isInternal: true)
        var policy = AlertPolicy()
        let snapshot = SystemSnapshot(volumes: [volume])
        XCTAssertTrue(policy.evaluate(enabled: [.ai, .storage], snapshot: snapshot, memoryPressure: false,
                                      usages: [.codex: usage], now: now).isEmpty)
        let alerts = policy.evaluate(enabled: [.ai, .storage], snapshot: snapshot, memoryPressure: false,
                                     usages: [.codex: usage], thresholds: restored.alertThresholds, now: now)
        XCTAssertEqual(Set(alerts.map(\.kind)), [.ai, .storage])
        XCTAssertTrue(policy.evaluate(enabled: [.ai, .storage], snapshot: snapshot, memoryPressure: false,
                                      usages: [.codex: usage], thresholds: restored.alertThresholds, now: now).isEmpty)
        model.updateAlertThresholds(ai: -1, storagePercent: 200, storageGB: 0)
        XCTAssertEqual(model.alertThresholds, AlertThresholds(aiRemainingPercent: 1, storageFreePercent: 100, storageFreeGB: 1))
    }

    func testSummaryUsesTheLimitingWindowAndRejectsStaleOrResetReadings() {
        let session = UsageWindow(id: "session", title: "5-hour", usedPercent: 30, resetsAt: now.addingTimeInterval(3600))
        let weekly = UsageWindow(id: "weekly", title: "Weekly", usedPercent: 82, resetsAt: now.addingTimeInterval(172800))
        let usage = SubscriptionUsage(plan: "pro", windows: [session, weekly], updatedAt: now)
        XCTAssertEqual(usage.limitingWindow(now: now), weekly)
        XCTAssertEqual(usage.limitingWindow(now: now)?.resetDescription(now: now), "Resets in 2d 0h")
        XCTAssertNil(usage.limitingWindow(now: now.addingTimeInterval(600)))
        XCTAssertNil(SubscriptionUsage(plan: nil, windows: [session, weekly], updatedAt: now.addingTimeInterval(3600))
            .limitingWindow(now: now.addingTimeInterval(3600)))
        XCTAssertNil(SubscriptionUsage(plan: nil, windows: [], updatedAt: now).limitingWindow(now: now))
    }

    func testDashboardOrderAndHiddenSectionsPersistWithoutChangingIcons() throws {
        let suite = "Glance.LayoutTests.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let model = AppModel(defaults: defaults, subscriptions: SubscriptionStore(defaults: defaults, startPolling: false))
        let icons = model.selected
        for _ in 0..<3 { model.moveSection(.subscriptions, by: -1) }
        model.hiddenSections = [.storage, .system]
        let restored = AppModel(defaults: defaults, subscriptions: SubscriptionStore(defaults: defaults, startPolling: false))
        XCTAssertEqual(restored.sectionOrder.first, .subscriptions)
        XCTAssertEqual(restored.hiddenSections, [.storage, .system])
        XCTAssertEqual(restored.selected, icons)
        XCTAssertFalse(restored.visibleSections.contains(.storage))
        model.hiddenSections = Set(DashboardSection.allCases)
        XCTAssertTrue(model.visibleSections.isEmpty)
        model.power.setActive(true)
        defer { model.power.stop() }
        XCTAssertEqual(model.visibleSections, [.awake], "A running session must retain its Stop control")
        XCTAssertEqual(DashboardSection.restored(["subscriptions", "battery", "unknown", "subscriptions"]),
                       [.subscriptions, .system, .storage, .awake])
    }

    func testDeniedNotificationPermissionDoesNotEnableAlerts() throws {
        let suite = "Glance.AlertPermissionTests.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let model = AppModel(defaults: defaults, subscriptions: SubscriptionStore(defaults: defaults, startPolling: false))
        XCTAssertTrue(model.enabledAlerts.isEmpty)
        model.authorizeAlerts = { $0(false, nil) }
        model.setAlertEnabled(.ai, true)
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        XCTAssertFalse(model.enabledAlerts.contains(.ai))
        XCTAssertNotNil(model.settingsError)
        model.authorizeAlerts = { $0(true, nil) }
        model.setAlertEnabled(.ai, true)
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        XCTAssertEqual(defaults.stringArray(forKey: "enabledAlerts"), ["ai"])
        model.setAlertEnabled(.ai, false)
        XCTAssertTrue(model.enabledAlerts.isEmpty)
    }

    func testAIAlertIsQuietThroughRepeatedAndMissingReadingsAndRearmsAfterRecovery() {
        var policy = AlertPolicy()
        func usage(_ used: Double, reset: TimeInterval = 3600) -> SubscriptionUsage {
            SubscriptionUsage(plan: nil, windows: [UsageWindow(id: "session", title: "5-hour", usedPercent: used,
                                                               resetsAt: now.addingTimeInterval(reset))], updatedAt: now)
        }
        func evaluate(_ readings: [SubscriptionProvider: SubscriptionUsage], at date: Date? = nil) -> [GlanceAlert] {
            policy.evaluate(enabled: [.ai], snapshot: SystemSnapshot(), memoryPressure: false, usages: readings, now: date ?? now)
        }
        XCTAssertTrue(evaluate([.codex: usage(79)]).isEmpty)
        let first = evaluate([.codex: usage(80)])
        XCTAssertEqual(first.count, 1)
        XCTAssertTrue(first.first?.body.contains("20% left · 5-hour") == true)
        XCTAssertTrue(evaluate([.codex: usage(90)]).isEmpty)
        XCTAssertTrue(evaluate([:]).isEmpty)
        XCTAssertTrue(evaluate([.codex: usage(90)]).isEmpty)
        XCTAssertTrue(evaluate([.codex: usage(50)]).isEmpty)
        XCTAssertEqual(evaluate([.codex: usage(90)]).count, 1)
        XCTAssertEqual(evaluate([.codex: usage(90, reset: 7200)]).count, 1)
        XCTAssertTrue(evaluate([.claude: usage(95)], at: now.addingTimeInterval(600)).isEmpty)
        XCTAssertTrue(evaluate([.claude: usage(95, reset: -1)]).isEmpty)
    }

    func testMemoryAlertRequiresContinuousPressureAndResetsAfterRecoveryOrDisable() {
        var policy = AlertPolicy()
        func evaluate(_ seconds: TimeInterval, pressure: Bool = true, enabled: Set<AlertKind> = [.memory]) -> [GlanceAlert] {
            policy.evaluate(enabled: enabled, snapshot: SystemSnapshot(), memoryPressure: pressure,
                            usages: [:], now: now.addingTimeInterval(seconds))
        }
        XCTAssertTrue(evaluate(0).isEmpty)
        XCTAssertTrue(evaluate(59).isEmpty)
        XCTAssertTrue(evaluate(59, pressure: false).isEmpty)
        XCTAssertTrue(evaluate(60).isEmpty)
        XCTAssertEqual(evaluate(120).count, 1)
        XCTAssertTrue(evaluate(180).isEmpty)
        XCTAssertTrue(evaluate(181, enabled: []).isEmpty)
        XCTAssertTrue(evaluate(182).isEmpty)
        XCTAssertEqual(evaluate(242).count, 1)
    }

    func testSwitchingBetweenAlreadyLowAIWindowsDoesNotRepeatWarnings() {
        var policy = AlertPolicy()
        func evaluate(session: Double, weekly: Double) -> [GlanceAlert] {
            let usage = SubscriptionUsage(plan: nil, windows: [
                UsageWindow(id: "session", title: "5-hour", usedPercent: session, resetsAt: now.addingTimeInterval(3600)),
                UsageWindow(id: "weekly", title: "Weekly", usedPercent: weekly, resetsAt: now.addingTimeInterval(86400))
            ], updatedAt: now)
            return policy.evaluate(enabled: [.ai], snapshot: SystemSnapshot(), memoryPressure: false,
                                   usages: [.codex: usage], now: now)
        }
        XCTAssertEqual(evaluate(session: 85, weekly: 82).count, 1)
        XCTAssertEqual(evaluate(session: 85, weekly: 90).count, 1)
        XCTAssertTrue(evaluate(session: 95, weekly: 90).isEmpty)
        XCTAssertTrue(evaluate(session: 95, weekly: 98).isEmpty)
    }

    func testDiskAlertUsesBothThresholdsAndSurvivesDisconnectWithoutRepeating() {
        var policy = AlertPolicy()
        func evaluate(_ available: Int64?, total: Int64 = 100_000_000_000) -> [GlanceAlert] {
            let volumes = available.map { [StorageVolume(id: "external", name: "Drive", path: "/Volumes/Drive",
                                                         total: total, available: $0, isInternal: false)] } ?? []
            return policy.evaluate(enabled: [.storage], snapshot: SystemSnapshot(volumes: volumes),
                                   memoryPressure: false, usages: [:], now: now)
        }
        XCTAssertTrue(evaluate(6_000_000_000).isEmpty)
        XCTAssertTrue(evaluate(12_000_000_000, total: 1_000_000_000_000).isEmpty)
        XCTAssertEqual(evaluate(4_000_000_000).count, 1)
        XCTAssertTrue(evaluate(nil).isEmpty)
        XCTAssertTrue(evaluate(3_000_000_000).isEmpty)
        XCTAssertTrue(evaluate(8_000_000_000).isEmpty)
        XCTAssertEqual(evaluate(4_000_000_000).count, 1)
    }
}
