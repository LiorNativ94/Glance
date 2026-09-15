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
    let popover = NSPopover()
    private(set) var statusItem: NSStatusItem!
    private let popoverAnchor = PopoverAnchorView()
    private var lastWidth: CGFloat = 0
    private var metricButtons: [String: NSButton] = [:]
    private(set) var notch: NotchController?
    private var alerts: AlertNotifications?
    private var localMonitor: Any?
    private var globalMonitor: Any?
    deinit {
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
        NotificationCenter.default.removeObserver(self)
    }
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Reopening Glance should reveal the existing instance rather than duplicate menu items.
        let others = NSRunningApplication.runningApplications(withBundleIdentifier: Bundle.main.bundleIdentifier ?? "com.liornativ.Glance")
            .filter { $0.processIdentifier != getpid() }
        if let existing = others.first { existing.activate(); NSApp.terminate(nil); return }
        configureMenuBar(model: AppModel())
        alerts = AlertNotifications(model: model)
        alerts?.openAlert = { [weak self] alert in self?.reviewAlert(alert) }
        if CommandLine.arguments.contains("--show") { DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { self.showDashboard() } }
    }
    func configureMenuBar(model: AppModel) {
        self.model = model
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.target = self
        statusItem.button?.action = #selector(togglePopover)
        statusItem.button?.addSubview(popoverAnchor)
        // Wait for the status window's final position, not the button's intermediate resize.
        if let window = statusItem.button?.window {
            NotificationCenter.default.addObserver(self, selector: #selector(updatePopoverAnchor),
                                                   name: NSWindow.didMoveNotification, object: window)
        }
        popover.behavior = .applicationDefined
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .keyDown]) { [weak self] event in
            guard let self, self.popover.isShown else { return event }
            if event.type == .keyDown, event.keyCode == 53 { self.popover.performClose(nil); return nil }
            if event.type != .keyDown, event.window !== self.statusItem.button?.window,
               event.window !== self.popover.contentViewController?.view.window { self.popover.performClose(nil) }
            return event
        }
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            self?.popover.performClose(nil)
        }
        popover.appearance = model.appearance.native
        model.onAppearanceChange = { [weak self] in self?.popover.appearance = self?.model.appearance.native }
        popover.animates = true
        popover.delegate = self
        let host = NSHostingController(rootView: Dashboard(model: model, power: model.power))
        host.sizingOptions = [.preferredContentSize]
        popover.contentViewController = host
        model.onMenuChange = { [weak self] in self?.updateStatus() }
        model.onRouteChange = { [weak self] in self?.resizeDetails(); self?.notch?.update(); self?.updatePopoverAnchor() }
        notch = NotchController(model: model)
        notch?.onExpand = { [weak self] in self?.popover.performClose(nil) }
        model.onNotchChange = { [weak self] in
            DispatchQueue.main.async { self?.updateDisplayMode() }
        }
        statusItem.isVisible = !model.showInNotch
        updateStatus()
    }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showDashboard(); return true
    }
    func applicationWillTerminate(_ notification: Notification) { model?.power.stop() }
    @objc private func togglePopover() {
        if popover.isShown { popover.performClose(nil) } else { showPopover() }
    }
    private func resizeDetails() {
        guard !model.showInNotch, model.detailMetric != nil else { return }
        let screen = statusItem?.button?.window?.screen ?? NSScreen.main
        let height = min(560, max(180, (screen?.visibleFrame.height ?? 620) - 60))
        if model.detailHeight != height { model.detailHeight = height }
    }
    @objc private func updatePopoverAnchor() {
        guard let button = statusItem?.button else { return }
        // A fixed-size view prevents AppKit from clipping the anchor when the button shrinks.
        popoverAnchor.frame = NSRect(x: button.bounds.midX - 0.5, y: button.bounds.minY,
                                     width: 1, height: button.bounds.height)
        if popover.isShown { popover.positioningRect = popoverAnchor.bounds }
    }
    private func updateDisplayMode() {
        let wasOpen = popover.isShown || notch?.expanded == true
        if model.showInNotch { popover.close() }
        statusItem.isVisible = !model.showInNotch
        notch?.update()
        if model.showInNotch {
            if wasOpen { notch?.expand(resetPage: false) }
        } else {
            updateStatus()
            if wasOpen {
                // Give the restored status item a layout pass before anchoring its dropdown.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
                    guard let self, !self.model.showInNotch else { return }
                    self.showPopover(resetPage: false)
                }
            }
        }
    }
    private func showDashboard() {
        model.goHome()
        if model.showInNotch { notch?.expand() } else { showPopover() }
    }
    func reviewAlert(_ alert: GlanceAlert) {
        model.alertToReview = alert
        if alert.kind == .ai, let provider = alert.id.split(separator: ":").dropFirst().first { model.openMetric(String(provider)) }
        else if alert.kind == .ai { model.page = .subscriptions }
        else if alert.kind == .memory { model.openMetric("memory") }
        else { model.page = .alertDetail }
        if model.showInNotch { notch?.expand(resetPage: false) }
        else { showPopover(resetPage: false) }
    }
    private func showPopover(resetPage: Bool = true) {
        guard !model.showInNotch else { return }
        guard statusItem?.button != nil else { return }
        guard !popover.isShown else { return }
        notch?.collapse()
        if resetPage { model.page = .overview }
        NSApp.activate(ignoringOtherApps: true)
        resizeDetails()
        updatePopoverAnchor()
        model.panelVisible = true
        popover.show(relativeTo: popoverAnchor.bounds, of: popoverAnchor, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
    }
    func popoverDidClose(_ notification: Notification) {
        if notch?.expanded != true { model.panelVisible = false }
    }
    @objc private func metricClicked(_ sender: NSButton) {
        let id = sender.identifier?.rawValue ?? "glance"
        if popover.isShown, model.detailMetric == id || (model.page == .overview && !["cpu", "memory", "claude", "codex"].contains(id)) { popover.performClose(nil); return }
        model.openMetric(id)
        if !popover.isShown { showPopover(resetPage: false) }
    }
    private func updateStatus() {
        guard let button = statusItem?.button else { return }
        var ids = model.visibleMetrics
        if ids.isEmpty { ids = ["glance"] }
        if model.showAwakeIcon && model.power.active { ids.append("awake") }
        for id in Array(metricButtons.keys) where !ids.contains(id) { metricButtons.removeValue(forKey: id)?.removeFromSuperview() }
        let font = NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .medium)
        var x: CGFloat = 5
        for id in ids {
            let value = ["glance", "awake"].contains(id) ? "" : model.value(for: id)
            let width: CGFloat = value.isEmpty ? 16 : 45
            let control: NSButton
            if let existing = metricButtons[id] { control = existing }
            else {
                control = NSButton(); control.isBordered = false
                control.target = self; control.action = #selector(metricClicked(_:))
                control.identifier = NSUserInterfaceItemIdentifier(id)
                control.setAccessibilityIdentifier("metric-" + id)
                button.addSubview(control); metricButtons[id] = control
            }
            let icon = id == "glance" ? "glance" : id == "awake" ? "cup.and.saucer" : model.icon(for: id)
            let rendered = NSImage(size: NSSize(width: width, height: 22), flipped: false) { _ in
                MetricIcons.image(icon).draw(in: NSRect(x: 0, y: 3, width: 16, height: 16))
                if !value.isEmpty {
                    let text = value as NSString
                    let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.labelColor]
                    text.draw(at: NSPoint(x: width - text.size(withAttributes: attrs).width, y: 5), withAttributes: attrs)
                }
                return true
            }
            rendered.isTemplate = true
            control.image = rendered; control.imagePosition = .imageOnly
            control.frame = NSRect(x: x, y: 0, width: width, height: 22)
            control.toolTip = id == "glance" ? "Open Glance" : "Open \(model.name(for: id)) details"
            control.setAccessibilityLabel(id == "glance" ? "Open Glance" : "\(model.name(for: id)): \(value)")
            x += width + 5
        }
        button.image = nil; button.title = ""
        button.setAccessibilityLabel("Glance")
        button.setAccessibilityIdentifier("glance-menu-bar")
        if x != lastWidth { statusItem.length = x; lastWidth = x }
    }
}

private final class PopoverAnchorView: NSView {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}
