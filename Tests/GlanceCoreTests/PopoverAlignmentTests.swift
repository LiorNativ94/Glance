import AppKit
import XCTest
import Vision
@testable import Glance

final class PopoverAlignmentTests: XCTestCase {
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
        XCTAssertTrue(button.hitTest(center) === button, "The anchor must not intercept menu bar clicks",
                      file: file, line: line)
    }
}
