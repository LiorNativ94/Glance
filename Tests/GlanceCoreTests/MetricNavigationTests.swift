import AppKit
import SwiftUI
import XCTest
import Vision
import GlanceCore
@testable import Glance

final class MetricNavigationTests: XCTestCase {
    func testMetricButtonsOpenSwitchCloseAndReturnHomeAcrossModes() throws {
        _ = NSApplication.shared
        let suite = "Glance.MetricNavigation.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(["cpu", "memory", "claude", "codex"], forKey: "selectedMetrics")
        defaults.set(["claude", "codex"], forKey: "subscriptionProviders")
        let store = SubscriptionStore(defaults: defaults, startPolling: false, fetch: { provider, _ in
            SubscriptionUsage(plan: "Fixture", windows: [UsageWindow(id: "seven_day", title: "Weekly", usedPercent: 38,
                resetsAt: Date.now.addingTimeInterval(86400), durationSeconds: 604800)], accountID: "fixture-" + provider.rawValue)
        })
        let model = AppModel(defaults: defaults, subscriptions: store)
        model.hiddenSections = Set(DashboardSection.allCases)
        let delegate = AppDelegate()
        delegate.configureMenuBar(model: model)
        defer { delegate.popover.close(); delegate.notch?.collapse(); delegate.notch?.panel.orderOut(nil); NSStatusBar.system.removeStatusItem(delegate.statusItem) }
        store.refreshAll()
        settle()
        let root = try XCTUnwrap(delegate.statusItem.button)
        for id in ["cpu", "memory", "claude", "codex"] {
            let button = try XCTUnwrap(root.subviews.compactMap { $0 as? NSButton }.first { $0.identifier?.rawValue == id })
            button.performClick(nil); settle()
            XCTAssertEqual(model.page, .metric(id))
            XCTAssertTrue(delegate.popover.isShown)
            XCTAssertEqual(model.processes.active, ["cpu", "memory"].contains(id))
            let view = try XCTUnwrap(delegate.popover.contentViewController?.view)
            XCTAssertEqual(view.frame.width, 360, accuracy: 1)
            let text = try renderedText(view, name: id)
            XCTAssertTrue(text.contains("Back to Glance"), text)
            XCTAssertTrue(text.contains(id == "cpu" ? "CPU" : id.capitalized), text)
            button.performClick(nil); settle()
            XCTAssertFalse(delegate.popover.isShown)
            XCTAssertFalse(model.processes.active)
        }
        let cpu = try XCTUnwrap(root.subviews.compactMap { $0 as? NSButton }.first { $0.identifier?.rawValue == "cpu" })
        let memory = try XCTUnwrap(root.subviews.compactMap { $0 as? NSButton }.first { $0.identifier?.rawValue == "memory" })
        cpu.performClick(nil); settle(); memory.performClick(nil); settle()
        XCTAssertTrue(delegate.popover.isShown)
        XCTAssertEqual(model.page, .metric("memory"))
        for notch in [true, false] {
            model.showInNotch = notch; settle()
            XCTAssertEqual(model.page, .metric("memory"))
            XCTAssertEqual(delegate.notch?.expanded, notch)
            XCTAssertEqual(delegate.popover.isShown, !notch)
        }
        model.goHome(); settle()
        XCTAssertEqual(model.page, .overview)
        XCTAssertTrue(delegate.popover.isShown)
        XCTAssertFalse(model.processes.active)
        XCTAssertEqual(model.hiddenSections, Set(DashboardSection.allCases))
        XCTAssertEqual(delegate.popover.contentViewController?.view.frame.width, 320)
        delegate.reviewAlert(.init(id: "ai:codex:weekly", kind: .ai, title: "Fixture", body: "Fixture")); settle()
        XCTAssertEqual(model.page, .metric("codex"))
        model.providerTabs[.codex] = "History"
        model.showInNotch = true; settle()
        XCTAssertEqual(model.providerTabs[.codex], "History")
        let notch = try XCTUnwrap(delegate.notch)
        let text = try renderedText(try XCTUnwrap(notch.panel.contentView), name: "codex-notch-history")
        XCTAssertTrue(text.contains("Back to Glance"), text)
        XCTAssertTrue(text.contains("Quota history"), text)
    }
    func testSubscriptionActivityAndHistoryRenderWithLocalFixtures() throws {
        _ = NSApplication.shared
        let suite = "Glance.MetricFixtures.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(suite)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { defaults.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: directory) }
        defaults.set(["claude"], forKey: "subscriptionProviders")
        defaults.set(["claude"], forKey: "localActivityProviders")
        defaults.set(["claude"], forKey: "selectedMetrics")
        let timestamp = ISO8601DateFormatter().string(from: .now)
        let log = """
        {"type":"assistant","timestamp":"\(timestamp)","requestId":"a","message":{"id":"a","model":"Sonnet","usage":{"input_tokens":100,"output_tokens":50}}}
        {"type":"assistant","timestamp":"\(timestamp)","requestId":"b","message":{"id":"b","model":"Opus","usage":{"input_tokens":200,"cache_read_input_tokens":70,"output_tokens":80}}}

        """
        try Data(log.utf8).write(to: directory.appendingPathComponent("fixture.jsonl"))
        let activity = LocalActivityStore(defaults: defaults, roots: { _ in [directory] })
        let history = QuotaHistoryStore(defaults: defaults, directory: directory)
        let store = SubscriptionStore(defaults: defaults, startPolling: false, fetch: { _, _ in
            SubscriptionUsage(plan: "Max", windows: [
                UsageWindow(id: "five_hour", title: "5-hour", usedPercent: 24, resetsAt: .now.addingTimeInterval(3600)),
                UsageWindow(id: "seven_day", title: "Weekly", usedPercent: 38, resetsAt: .now.addingTimeInterval(86400), durationSeconds: 604800)
            ], accountID: "fixture")
        })
        let model = AppModel(defaults: defaults, subscriptions: store, quotaHistory: history, localActivity: activity)
        model.providerTabs[.claude] = "Activity"
        let delegate = AppDelegate()
        delegate.configureMenuBar(model: model)
        defer { model.panelVisible = false; delegate.popover.close(); delegate.notch?.panel.orderOut(nil); NSStatusBar.system.removeStatusItem(delegate.statusItem) }
        store.refreshAll(); settle()
        let button = try XCTUnwrap(delegate.statusItem.button?.subviews.compactMap { $0 as? NSButton }.first)
        button.performClick(nil); settle()
        let view = try XCTUnwrap(delegate.popover.contentViewController?.view)
        let text = try renderedText(view, name: "claude-activity")
        XCTAssertTrue(text.contains("Sonnet"), text)
        XCTAssertTrue(text.contains("Opus"), text)
        XCTAssertTrue(text.contains("430 tokens"), text)
        XCTAssertTrue(text.contains("Excluding cached input"), text)
        XCTAssertTrue(text.contains("Token breakdown"), text)
        XCTAssertFalse(text.contains("Total processed"), text)
        XCTAssertTrue(text.contains("On this Mac"), text)
        XCTAssertTrue(text.contains("Back to Glance"), text)
        history.setEnabled(true)
        let reset = Date.now.addingTimeInterval(86400)
        for (seconds, value) in [(-600.0, 30.0), (-300, 34), (0, 38)] {
            history.record(.claude, SubscriptionUsage(plan: "Max", windows: [UsageWindow(id: "seven_day", title: "Weekly", usedPercent: value, resetsAt: reset)], updatedAt: .now.addingTimeInterval(seconds), accountID: "fixture"))
        }
        model.goHome(); settle(); model.providerTabs[.claude] = "Summary"; model.openMetric("claude"); settle()
        let summary = try renderedText(view, name: "claude-summary-history")
        XCTAssertTrue(summary.contains("62%"), summary)
        XCTAssertTrue(summary.contains("remaining"), summary)
        XCTAssertTrue(summary.contains("Quota history"), summary)
        XCTAssertFalse(summary.contains("8.0 pp"), summary)
        model.goHome(); settle(); model.providerTabs[.claude] = "History"; model.openMetric("claude"); settle()
        let historyText = try renderedText(view, name: "claude-history")
        XCTAssertTrue(historyText.contains("Observed consumption"), historyText)
        XCTAssertTrue(historyText.contains("8.0 pp"), historyText)
        XCTAssertTrue(historyText.contains("62.0% remaining"), historyText)
        XCTAssertTrue(historyText.contains("Manage history"), historyText)
        XCTAssertFalse(historyText.contains("Disable & delete"), historyText)
        history.clear()
        for (seconds, value) in [(-86400.0, 22.0), (-86100, 25), (-600, 30), (-300, 34), (0, 38)] {
            history.record(.claude, SubscriptionUsage(plan: "Max", windows: [UsageWindow(id: "seven_day", title: "Weekly", usedPercent: value, resetsAt: reset)], updatedAt: .now.addingTimeInterval(seconds), accountID: "fixture"))
        }
        settle()
        let chartText = try renderedText(view, name: "claude-history-chart")
        XCTAssertTrue(chartText.contains("Percentage points"), chartText)
        XCTAssertTrue(chartText.contains("62.0% remaining"), chartText)
        history.clear()
        XCTAssertTrue(history.history.observations.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.appendingPathComponent("quota-history.json").path))
    }
    func testCodexDetailsUseExistingAllowanceAndLocalActivity() throws {
        _ = NSApplication.shared
        let suite = "Glance.CodexExistingConnection.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(suite)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { defaults.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: directory) }
        defaults.set(["codex"], forKey: "subscriptionProviders")
        defaults.set(["codex"], forKey: "localActivityProviders")
        defaults.set(["codex"], forKey: "selectedMetrics")
        let timestamp = ISO8601DateFormatter().string(from: .now)
        let yesterday = ISO8601DateFormatter().string(from: .now.addingTimeInterval(-86400))
        let log = """
        {"type":"session_meta","timestamp":"\(yesterday)","payload":{"id":"fixture","cwd":"/tmp/sample"}}
        {"type":"turn_context","timestamp":"\(yesterday)","payload":{"model":"gpt-5"}}
        {"type":"event_msg","timestamp":"\(yesterday)","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":10000000,"cached_input_tokens":9000000,"output_tokens":1000000}}}}
        {"type":"event_msg","timestamp":"\(timestamp)","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":20000000,"cached_input_tokens":18000000,"output_tokens":2000000}}}}

        """
        try Data(log.utf8).write(to: directory.appendingPathComponent("fixture.jsonl"))
        let activity = LocalActivityStore(defaults: defaults, roots: { _ in [directory] })
        let store = SubscriptionStore(defaults: defaults, startPolling: false, fetch: { _, _ in
            SubscriptionUsage(plan: "Pro", windows: [UsageWindow(id: "seven_day", title: "Weekly", usedPercent: 84,
                resetsAt: .now.addingTimeInterval(86400), durationSeconds: 604800)], accountID: "fixture")
        })
        let model = AppModel(defaults: defaults, subscriptions: store, localActivity: activity)
        model.appearance = .dark
        let delegate = AppDelegate()
        delegate.configureMenuBar(model: model)
        defer { model.panelVisible = false; delegate.popover.close(); delegate.notch?.panel.orderOut(nil); NSStatusBar.system.removeStatusItem(delegate.statusItem) }
        store.refreshAll(); settle()
        let button = try XCTUnwrap(delegate.statusItem.button?.subviews.compactMap { $0 as? NSButton }.first)
        button.performClick(nil); settle()
        let view = try XCTUnwrap(delegate.popover.contentViewController?.view)
        let summary = try renderedText(view, name: "codex-existing-summary")
        XCTAssertTrue(summary.contains("Weekly"), summary)
        XCTAssertTrue(summary.contains("16%"), summary)
        XCTAssertTrue(summary.contains("Low"), summary)
        XCTAssertTrue(summary.contains("Usage resets"), summary)
        model.goHome(); settle(); model.providerTabs[.codex] = "Activity"; model.openMetric("codex"); settle()
        let activityText = try renderedText(view, name: "codex-existing-activity")
        XCTAssertTrue(activityText.contains("4M tokens"), activityText)
        XCTAssertTrue(activityText.contains("gpt-5"), activityText)
        XCTAssertTrue(activityText.contains("Token breakdown"), activityText)
        for text in [summary, activityText] {
            XCTAssertTrue(text.contains("Back to Glance"), text)
            XCTAssertFalse(text.localizedCaseInsensitiveContains("web analytics"), text)
            XCTAssertFalse(text.localizedCaseInsensitiveContains("sign-in"), text)
            XCTAssertFalse(text.localizedCaseInsensitiveContains("connect"), text)
        }
    }
    func testDashboardAppearanceMatchesAcrossModesAndNavigation() throws {
        _ = NSApplication.shared
        let suite = "Glance.Appearance.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(true, forKey: "showInNotch")
        let model = AppModel(defaults: defaults, subscriptions: SubscriptionStore(defaults: defaults, startPolling: false))
        XCTAssertEqual(model.appearance, .system)
        let delegate = AppDelegate()
        delegate.configureMenuBar(model: model)
        let notch = try XCTUnwrap(delegate.notch)
        defer { delegate.popover.close(); notch.collapse(); notch.panel.orderOut(nil); NSStatusBar.system.removeStatusItem(delegate.statusItem) }
        func background(_ view: NSView) throws -> NSColor {
            let bitmap = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: view.bounds))
            view.cacheDisplay(in: view.bounds, to: bitmap)
            return try XCTUnwrap(bitmap.colorAt(x: bitmap.pixelsWide / 2, y: bitmap.pixelsHigh - 8)?.usingColorSpace(.sRGB))
        }
        for appearance in [AppModel.Appearance.light, .dark, .system] {
            model.appearance = appearance
            model.showInNotch = true; notch.expand(); settle()
            XCTAssertEqual(defaults.string(forKey: "dashboardAppearance"), appearance.rawValue)
            XCTAssertEqual(notch.panel.appearance?.name, appearance.native?.name)
            XCTAssertEqual(delegate.popover.appearance?.name, appearance.native?.name)
            let isDark = notch.panel.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            let notchView = try XCTUnwrap(notch.panel.contentView)
            var notchColor: NSColor?
            for page in [AppModel.Page.metric("cpu"), .overview, .settings] {
                model.page = page; settle()
                let color = try background(notchView)
                if isDark { XCTAssertLessThan(color.redComponent, 0.2) }
                else { XCTAssertGreaterThan(color.redComponent, 0.9) }
                if let notchColor {
                    XCTAssertEqual(color.greenComponent, notchColor.greenComponent, accuracy: 0.015)
                    XCTAssertEqual(color.blueComponent, notchColor.blueComponent, accuracy: 0.015)
                }
                notchColor = color
            }
            let settings = try renderedText(notchView, name: "notch-\(appearance.rawValue)-settings")
            XCTAssertTrue(settings.contains("Appearance"), settings)
            XCTAssertTrue(settings.contains("Light"), settings)
            XCTAssertTrue(settings.contains("Dark"), settings)
            model.showInNotch = false; settle()
            XCTAssertTrue(delegate.popover.isShown)
            let menuView = try XCTUnwrap(delegate.popover.contentViewController?.view)
            for page in [AppModel.Page.metric("cpu"), .overview, .settings] {
                model.page = page; settle()
                let menuColor = try background(menuView)
                XCTAssertEqual(menuColor.redComponent, try XCTUnwrap(notchColor).redComponent, accuracy: 0.015)
                XCTAssertEqual(menuColor.greenComponent, try XCTUnwrap(notchColor).greenComponent, accuracy: 0.015)
                XCTAssertEqual(menuColor.blueComponent, try XCTUnwrap(notchColor).blueComponent, accuracy: 0.015)
            }
        }
        model.appearance = .dark
        let restored = AppModel(defaults: defaults, subscriptions: SubscriptionStore(defaults: defaults, startPolling: false))
        XCTAssertEqual(restored.appearance, .dark)
    }
    private func settle() { RunLoop.main.run(until: Date.now.addingTimeInterval(0.7)) }
    private func renderedText(_ view: NSView, name: String) throws -> String {
        let bitmap = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: view.bounds))
        view.cacheDisplay(in: view.bounds, to: bitmap)
        let directory = URL(fileURLWithPath: "/tmp/glance-detail-renders")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try bitmap.representation(using: .png, properties: [:])?.write(to: directory.appendingPathComponent(name + ".png"))
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        try VNImageRequestHandler(cgImage: XCTUnwrap(bitmap.cgImage)).perform([request])
        return (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }.joined(separator: " ")
    }
}
