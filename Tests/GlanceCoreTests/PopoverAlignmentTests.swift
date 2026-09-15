import AppKit
import XCTest
import Vision
import GlanceCore
@testable import Glance

final class PopoverAlignmentTests: XCTestCase {
    func testNotchDropdownIsCenteredUnderHeaderForOddAndEvenIconCounts() throws {
        _ = NSApplication.shared
        let suite = "Glance.NotchCenterTests.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(true, forKey: "showInNotch")
        defaults.set(["claude", "codex"], forKey: "subscriptionProviders")
        let model = AppModel(defaults: defaults, subscriptions: SubscriptionStore(defaults: defaults, startPolling: false))
        let notch = NotchController(model: model)
        defer { notch.collapse(); notch.panel.orderOut(nil) }
        for selection in [["cpu", "memory", "codex"], ["cpu", "memory"], ["codex"], ["cpu", "memory", "codex", "claude"], []] {
            model.selected = selection
            notch.collapse()
            settleLayout()
            let headerFrame = notch.panel.frame
            notch.expand()
            settleLayout()
            XCTAssertEqual(notch.dashboardFrame.midX, headerFrame.midX, accuracy: 1,
                           "Dropdown must be centered under the whole header for \(selection.count) icons")
        }
    }
    func testNotchKeepsItsHostingViewWhenOpeningAlertsAndResizing() throws {
        _ = NSApplication.shared
        let suite = "Glance.NotchAlertHostTests.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(true, forKey: "showInNotch")
        let model = AppModel(defaults: defaults, subscriptions: SubscriptionStore(defaults: defaults, startPolling: false))
        let notch = NotchController(model: model)
        defer { notch.collapse(); notch.panel.orderOut(nil) }
        notch.expand()
        let host = try XCTUnwrap(notch.panel.contentView)
        model.page = .alerts
        notch.update()
        XCTAssertTrue(notch.panel.contentView === host, "Resizing Alerts must not recreate its hosting view and restart its layout callbacks")
    }
    func testDeniedPermissionStaysInsideTheNotchWithoutOpeningAnotherWindow() throws {
        _ = NSApplication.shared
        let suite = "Glance.NotchPermissionTests.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(true, forKey: "showInNotch")
        let model = AppModel(defaults: defaults, subscriptions: SubscriptionStore(defaults: defaults, startPolling: false))
        let delegate = AppDelegate()
        delegate.configureMenuBar(model: model)
        let notch = try XCTUnwrap(delegate.notch)
        defer {
            model.settingsError = nil
            notch.collapse(); notch.panel.orderOut(nil)
            delegate.popover.close()
            NSStatusBar.system.removeStatusItem(delegate.statusItem)
        }
        notch.expand()
        model.page = .settings
        settleLayout()
        model.page = .alerts
        settleLayout()
        let existingWindows = Set(NSApp.windows.filter(\.isVisible).map(ObjectIdentifier.init))
        let host = try XCTUnwrap(notch.panel.contentView)
        let top = notch.panel.frame.maxY
        model.authorizeAlerts = { $0(false, nil) }
        model.setAlertEnabled(.ai, true)
        settleLayout()
        XCTAssertFalse(model.enabledAlerts.contains(.ai))
        XCTAssertNotNil(model.settingsError)
        XCTAssertTrue(notch.panel.contentView === host)
        XCTAssertTrue(notch.expanded)
        XCTAssertFalse(delegate.popover.isShown)
        XCTAssertEqual(notch.panel.frame.maxY, top, accuracy: 1)
        XCTAssertTrue(NSApp.windows.filter { $0.isVisible && !existingWindows.contains(ObjectIdentifier($0)) }.isEmpty,
                      "Permission errors must stay in the active dashboard instead of opening a stray window")
        let settledFrame = notch.panel.frame
        settleLayout()
        XCTAssertEqual(notch.panel.frame, settledFrame, "Alerts layout must settle rather than repeatedly resize")
        let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: bitmap)
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        try VNImageRequestHandler(cgImage: XCTUnwrap(bitmap.cgImage)).perform([request])
        let text = (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }.joined(separator: " ")
        XCTAssertTrue(text.contains("Allow Glance notifications"), text)
        XCTAssertTrue(text.contains("remaining"), text)
    }
    func testAlertsOpenTheirDetailsInEitherDisplayModeWithoutChangingHiddenSections() throws {
        _ = NSApplication.shared
        let suite = "Glance.AlertNavigationTests.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let model = AppModel(defaults: defaults, subscriptions: SubscriptionStore(defaults: defaults, startPolling: false))
        model.hiddenSections = Set(DashboardSection.allCases)
        let delegate = AppDelegate()
        delegate.configureMenuBar(model: model)
        defer {
            delegate.popover.close()
            delegate.notch?.panel.orderOut(nil)
            NSStatusBar.system.removeStatusItem(delegate.statusItem)
        }
        for notch in [false, true] {
            model.showInNotch = notch
            settleLayout()
            for kind in AlertKind.allCases {
                let alert = GlanceAlert(id: kind.rawValue, kind: kind, title: kind.title, body: "Test condition")
                delegate.reviewAlert(alert)
                settleLayout()
                XCTAssertEqual(model.page, kind == .ai ? .subscriptions : kind == .memory ? .metric("memory") : .alertDetail)
                XCTAssertEqual(model.alertToReview, alert)
                XCTAssertEqual(model.hiddenSections, Set(DashboardSection.allCases))
                XCTAssertEqual(delegate.popover.isShown, !notch)
                XCTAssertEqual(delegate.notch?.expanded, notch)
            }
        }
    }
    func testNotchUsesOnlySelectedMetricsAndShrinksWithSelection() throws {
        _ = NSApplication.shared
        let suite = "Glance.NotchSelectionTests.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(true, forKey: "showInNotch")
        defaults.set(["claude", "codex"], forKey: "subscriptionProviders")
        defaults.set(["cpu", "memory", "codex"], forKey: "selectedMetrics")
        let store = SubscriptionStore(defaults: defaults, startPolling: false)
        let model = AppModel(defaults: defaults, subscriptions: store)
        let notch = NotchController(model: model)
        defer { notch.panel.orderOut(nil) }
        settleLayout()
        let threeMetricWidth = notch.panel.frame.width
        var previousWidth = notch.panel.frame.width
        let top = notch.panel.frame.maxY
        for selection in [["cpu", "codex"], ["codex"], []] {
            model.selected = selection
            settleLayout()
            XCTAssertLessThan(notch.panel.frame.width, previousWidth)
            XCTAssertEqual(notch.panel.frame.maxY, top)
            previousWidth = notch.panel.frame.width
        }
        let screen = try XCTUnwrap(notch.panel.screen)
        let cameraWidth = (screen.auxiliaryTopRightArea?.minX ?? screen.frame.midX)
            - (screen.auxiliaryTopLeftArea?.maxX ?? screen.frame.midX)
        XCTAssertLessThanOrEqual(previousWidth - cameraWidth, 30, "An empty selection must leave only a tiny fallback button, even with both providers connected")
        notch.expand()
        model.page = .customize
        model.selected = ["claude", "cpu", "memory", "codex"]
        settleLayout()
        XCTAssertTrue(notch.expanded)
        XCTAssertEqual(model.page, .customize)
        notch.collapse()
        XCTAssertGreaterThan(notch.panel.frame.width, threeMetricWidth, "All four selected icons must fit without truncation")
        XCTAssertEqual(notch.panel.frame.maxY, top)
    }

    func testDisplayModesAreExclusiveAndSwitchingKeepsDashboardAccessible() throws {
        _ = NSApplication.shared
        let suite = "Glance.DisplayModeTests.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let model = AppModel(defaults: defaults)
        let delegate = AppDelegate()
        delegate.configureMenuBar(model: model)
        defer {
            delegate.popover.close()
            delegate.notch?.panel.orderOut(nil)
            NSStatusBar.system.removeStatusItem(delegate.statusItem)
        }
        settleLayout()
        XCTAssertTrue(delegate.statusItem.isVisible)
        delegate.statusItem.button?.performClick(nil)
        settleLayout()
        for _ in 0..<2 {
            model.showInNotch = true
            settleLayout()
            XCTAssertFalse(delegate.statusItem.isVisible)
            XCTAssertFalse(delegate.popover.isShown)
            XCTAssertTrue(delegate.notch?.panel.isVisible == true)
            XCTAssertTrue(delegate.notch?.expanded == true)
            model.showInNotch = false
            settleLayout()
            XCTAssertTrue(delegate.statusItem.isVisible)
            XCTAssertTrue(delegate.popover.isShown)
            XCTAssertFalse(delegate.notch?.panel.isVisible == true)
            assertCentered(delegate)
        }
        model.showInNotch = true
        settleLayout()
        delegate.notch?.collapse()
        _ = delegate.applicationShouldHandleReopen(NSApplication.shared, hasVisibleWindows: false)
        settleLayout()
        XCTAssertTrue(delegate.notch?.expanded == true)
        XCTAssertFalse(delegate.statusItem.isVisible)
        XCTAssertTrue(AppModel(defaults: defaults).showInNotch)
    }

    func testNotchShowsSubscriptionReadingsAndPreservesTopEdge() throws {
        _ = NSApplication.shared
        let suite = "Glance.NotchTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(true, forKey: "showInNotch")
        defaults.set(["claude", "codex"], forKey: "subscriptionProviders")
        let store = SubscriptionStore(defaults: defaults, startPolling: false, fetch: { provider, _ in
            SubscriptionUsage(plan: provider == .claude ? "max" : "pro", windows: [
                UsageWindow(id: "session", title: "5-hour", usedPercent: 24, resetsAt: Date().addingTimeInterval(3600)),
                UsageWindow(id: "weekly", title: "Weekly", usedPercent: 65, resetsAt: Date().addingTimeInterval(172800))
            ])
        })
        let model = AppModel(defaults: defaults, subscriptions: store)
        let notch = NotchController(model: model)
        defer { notch.panel.orderOut(nil) }
        store.refreshAll()
        settleLayout()
        XCTAssertTrue(notch.panel.isVisible)
        let collapsedHeight = notch.panel.frame.height
        let screen = try XCTUnwrap(notch.panel.screen)
        XCTAssertGreaterThanOrEqual(notch.panel.frame.minY, screen.frame.maxY - max(24, screen.safeAreaInsets.top))
        let top = notch.panel.frame.maxY
        notch.toggle()
        settleLayout()
        XCTAssertTrue(notch.expanded)
        XCTAssertLessThan(notch.panel.frame.height, 600 + collapsedHeight, "The notch should fit the dashboard without empty space below it")
        XCTAssertEqual(notch.panel.frame.maxY, top, accuracy: 1)
        model.page = .subscriptions
        settleLayout()
        XCTAssertEqual(notch.panel.frame.maxY, top, accuracy: 1)
        let view = try XCTUnwrap(notch.panel.contentView)
        let bitmap = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: view.bounds))
        view.cacheDisplay(in: view.bounds, to: bitmap)
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        try VNImageRequestHandler(cgImage: XCTUnwrap(bitmap.cgImage)).perform([request])
        let text = (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }.joined(separator: " ")
        XCTAssertTrue(text.contains("Claude"), text)
        XCTAssertTrue(text.contains("76% left"), text)
        XCTAssertTrue(text.contains("Weekly"), text)
        XCTAssertEqual(store.remaining(.codex), 0.35)
        let subscriptionHeight = notch.panel.frame.height
        model.page = .settings
        settleLayout()
        XCTAssertNotEqual(notch.panel.frame.height, subscriptionHeight, "Settings should resize to fit its content")
        XCTAssertLessThanOrEqual(notch.panel.frame.height, 600 + collapsedHeight)
        XCTAssertEqual(notch.panel.frame.maxY, top, accuracy: 1)
        notch.collapse()
        XCTAssertEqual(notch.panel.frame.height, collapsedHeight)
        XCTAssertEqual(notch.panel.frame.maxY, top, accuracy: 1)
        model.showInNotch = false
        notch.update()
        XCTAssertFalse(notch.panel.isVisible)
    }

    func testSettingsShowsBundledVersion() throws {
        _ = NSApplication.shared
        let suite = "Glance.SettingsVersionTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let model = AppModel(defaults: defaults)
        model.page = .settings
        let delegate = AppDelegate()
        delegate.configureMenuBar(model: model)
        defer {
            delegate.popover.close()
            NSStatusBar.system.removeStatusItem(delegate.statusItem)
        }
        settleLayout()
        try XCTUnwrap(delegate.statusItem.button).performClick(nil)
        model.page = .settings
        settleLayout()
        XCTAssertTrue(delegate.popover.isShown)
        let view = try XCTUnwrap(delegate.popover.contentViewController?.view)
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Development"
        let bitmap = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: view.bounds))
        view.cacheDisplay(in: view.bounds, to: bitmap)
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        try VNImageRequestHandler(cgImage: XCTUnwrap(bitmap.cgImage)).perform([request])
        let text = (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }.joined(separator: " ")
        XCTAssertTrue(text.contains("Version \(version)"), text)
    }

    func testOpenPopoverTracksMenuBarCustomization() throws {
        _ = NSApplication.shared
        let suite = "Glance.PopoverAlignmentTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(["cpu", "memory"], forKey: "selectedMetrics")
        let model = AppModel(defaults: defaults)
        let delegate = AppDelegate()
        delegate.configureMenuBar(model: model)
        let button = try XCTUnwrap(delegate.statusItem.button)
        defer {
            delegate.popover.close()
            NSStatusBar.system.removeStatusItem(delegate.statusItem)
        }
        settleLayout()
        button.performClick(nil)
        model.page = .customize
        settleLayout()
        XCTAssertTrue(delegate.popover.isShown)
        assertCentered(delegate)
        for selection in [["cpu"], [], ["cpu", "memory"], [], ["memory"]] {
            let panel = try XCTUnwrap(delegate.popover.contentViewController?.view.window)
            var centers = [panel.frame.midX]
            let observer = NotificationCenter.default.addObserver(forName: NSWindow.didMoveNotification,
                                                                  object: panel, queue: .main) { _ in
                if abs(panel.frame.midX - centers.last!) > 0.5 { centers.append(panel.frame.midX) }
            }
            model.selected = selection
            settleLayout()
            NotificationCenter.default.removeObserver(observer)
            XCTAssertLessThanOrEqual(centers.count, 2, "An icon change should reposition the panel only once")
            XCTAssertTrue(delegate.popover.isShown)
            XCTAssertEqual(model.page, .customize)
            assertCentered(delegate)
        }
        // Rapid toggles must also settle at the latest selection's screen position.
        for selection in [[], ["cpu", "memory"], ["cpu"], [], ["memory", "cpu"]] {
            model.selected = selection
            RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        }
        settleLayout()
        XCTAssertTrue(delegate.popover.isShown)
        XCTAssertEqual(model.page, .customize)
        assertCentered(delegate)
        delegate.popover.close()
        model.selected = ["cpu"]
        settleLayout()
        button.performClick(nil)
        settleLayout()
        XCTAssertTrue(delegate.popover.isShown)
        XCTAssertEqual(model.page, .overview)
        assertCentered(delegate)
    }

    private func settleLayout() {
        // The status window moves later than the button's frame notification.
        RunLoop.main.run(until: Date().addingTimeInterval(0.7))
    }

    private func assertCentered(_ delegate: AppDelegate, file: StaticString = #filePath, line: UInt = #line) {
        let button = delegate.statusItem.button!
        let buttonFrame = button.window!.convertToScreen(button.convert(button.bounds, to: nil))
        let panel = delegate.popover.contentViewController!.view.window!
        XCTAssertEqual(panel.frame.midX, buttonFrame.midX, accuracy: 1,
                       "Visible panel must stay centered under the menu bar item", file: file, line: line)
        let center = button.convert(NSPoint(x: button.bounds.midX, y: button.bounds.midY), to: button.superview)
        XCTAssertTrue(button.hitTest(center) is NSButton, "Each metric must remain clickable; the anchor must not intercept clicks",
                      file: file, line: line)
    }
}
