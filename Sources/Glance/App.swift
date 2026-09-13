import AppKit
import SwiftUI
import GlanceCore

@main
struct GlanceApp {
    static func main() {
        if CommandLine.arguments.contains("--diagnostics") {
            let reader = SystemReader()
            _ = reader.read(); Thread.sleep(forTimeInterval: 1)
            let s = reader.read()
            print("CPU: \(ReadingFormat.percent(s.cpu))")
            print("Memory: \(ReadingFormat.memory(s.memoryUsed, total: s.memoryTotal))")
            print("Battery: \(ReadingFormat.percent(s.battery?.fraction))")
            for v in s.volumes { print("\(v.name): \(v.used) / \(v.total) bytes; \(v.available) available; id=\(v.id)") }
            print("System sleep disabled: \(String(describing: SystemReader.systemSleepDisabled()))")
            return
        }
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        let delegate = AppDelegate()
        app.delegate = delegate
        withExtendedLifetime(delegate) { app.run() }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate {
    private var model: AppModel!
    private let popover = NSPopover()
    private var statusItem: NSStatusItem!
    private var lastWidth: CGFloat = 0
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Reopening Glance should reveal the existing instance rather than duplicate menu items.
        let others = NSRunningApplication.runningApplications(withBundleIdentifier: Bundle.main.bundleIdentifier ?? "com.liornativ.Glance")
            .filter { $0.processIdentifier != getpid() }
        if let existing = others.first { existing.activate(); NSApp.terminate(nil); return }
        model = AppModel()
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.target = self
        statusItem.button?.action = #selector(togglePopover)
        popover.behavior = .transient
        popover.animates = true
        popover.delegate = self
        let host = NSHostingController(rootView: Dashboard(model: model, power: model.power))
        host.sizingOptions = [.preferredContentSize]
        popover.contentViewController = host
        model.onMenuChange = { [weak self] in self?.updateStatus() }
        updateStatus()
        if CommandLine.arguments.contains("--show") { DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { self.showPopover() } }
    }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showPopover(); return true
    }
    func applicationWillTerminate(_ notification: Notification) { model?.power.stop() }
    @objc private func togglePopover() {
        if popover.isShown { popover.performClose(nil) } else { showPopover() }
    }
    private func showPopover() {
        guard let button = statusItem?.button else { return }
        guard !popover.isShown else { return }
        model.page = .overview
        NSApp.activate(ignoringOtherApps: true)
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
    }
    private func updateStatus() {
        guard let button = statusItem?.button else { return }
        var items = model.visibleMetrics.map { (model.icon(for: $0), model.value(for: $0)) }
        if items.isEmpty { items = [("waveform.path.ecg", "")] }
        if model.showAwakeIcon && model.power.active { items.append(("cup.and.saucer", "")) }
        // Fixed-width digit cells keep neighboring menu items from shifting as percentages change.
        let font = NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .medium)
        let widths = items.map { $0.1.isEmpty ? CGFloat(16) : CGFloat(45) }
        let width = widths.reduce(0, +) + CGFloat(max(0, items.count - 1)) * 5
        let image = NSImage(size: NSSize(width: width, height: 22), flipped: false) { rect in
            var x: CGFloat = 0
            for (index, item) in items.enumerated() {
                let icon = MetricIcons.image(item.0)
                icon.draw(in: NSRect(x: x, y: 3, width: 16, height: 16))
                if !item.1.isEmpty {
                    let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.labelColor]
                    let text = item.1 as NSString
                    let textWidth = text.size(withAttributes: attrs).width
                    text.draw(at: NSPoint(x: x + widths[index] - textWidth, y: 5), withAttributes: attrs)
                }
                x += widths[index] + 5
            }
            return true
        }
        image.isTemplate = true
        button.image = image
        button.imagePosition = .imageOnly
        button.title = ""
        button.toolTip = model.visibleMetrics.isEmpty ? "Glance — open dashboard" : model.visibleMetrics.map { "\(model.name(for: $0)): \(model.value(for: $0))" }.joined(separator: " · ")
        button.setAccessibilityLabel("Glance")
        button.setAccessibilityValue(button.toolTip)
        button.setAccessibilityIdentifier("glance-menu-bar")
        if width != lastWidth { statusItem.length = width + 10; lastWidth = width }
    }
}
