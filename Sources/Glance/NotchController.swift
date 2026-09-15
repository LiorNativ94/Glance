import AppKit
import Combine
import SwiftUI
import GlanceCore

final class NotchController {
    private let model: AppModel
    let panel: NSPanel
    private(set) var expanded = false
    private(set) var dashboardFrame = NSRect.zero
    private var dashboardHeight: CGFloat = 600
    private var observers: [NSObjectProtocol] = []
    private var localMonitor: Any?
    private var globalMonitor: Any?
    private var modelChanges: AnyCancellable?
    private var displayedMetrics: [String] = []
    private var hostingView: NSHostingView<NotchContent>?
    var onExpand: (() -> Void)?

    init(model: AppModel) {
        self.model = model
        panel = NotchPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isReleasedWhenClosed = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.appearance = model.appearance.native
        panel.hasShadow = true
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.hidesOnDeactivate = false
        panel.setAccessibilityLabel("Glance notch")
        observers.append(NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
                                                                object: nil, queue: .main) { [weak self] _ in self?.update() })
        observers.append(NotificationCenter.default.addObserver(forName: NSWindow.didResignKeyNotification,
                                                                object: panel, queue: .main) { [weak self] _ in self?.collapse() })
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .keyDown]) { [weak self] event in
            guard let self, self.expanded else { return event }
            if event.type == .keyDown, event.keyCode == 53, event.window === self.panel {
                self.collapse(); return nil
            }
            if event.type != .keyDown, event.window !== self.panel { self.collapse() }
            return event
        }
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            self?.collapse()
        }
        modelChanges = model.objectWillChange.sink { [weak self] in
            DispatchQueue.main.async {
                guard let self else { return }
                self.panel.appearance = self.model.appearance.native
                guard self.model.visibleMetrics != self.displayedMetrics else { return }
                self.update()
            }
        }
        update()
    }
    deinit {
        observers.forEach { NotificationCenter.default.removeObserver($0) }
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
        panel.orderOut(nil)
    }

    func toggle() {
        if expanded && model.page != .overview { model.goHome(); update() }
        else if expanded { collapse() } else { expand() }
    }
    func expand(resetPage: Bool = true) {
        guard model.showInNotch else { return }
        expanded = true
        model.panelVisible = true
        onExpand?()
        if resetPage { model.page = .overview }
        update()
        panel.makeKey()
    }
    func collapse() {
        guard expanded else { return }
        expanded = false
        model.panelVisible = false
        update()
    }
    func update() {
        guard model.showInNotch else { expanded = false; panel.orderOut(nil); return }
        guard let screen = NSScreen.screens.first(where: { $0.safeAreaInsets.top > 0 }) ?? NSScreen.main ?? NSScreen.screens.first else {
            panel.orderOut(nil); return
        }
        let metrics = model.visibleMetrics
        displayedMetrics = metrics
        let split = (metrics.count + 1) / 2
        let leftMetrics = Array(metrics.prefix(split))
        let rightMetrics = Array(metrics.dropFirst(split))
        let leftWidth = Self.wingWidth(count: leftMetrics.count, fallback: metrics.isEmpty)
        let rightWidth = Self.wingWidth(count: rightMetrics.count)
        let header = Self.headerFrame(screen: screen.frame, safeAreaTop: screen.safeAreaInsets.top,
                                      menuBarHeight: screen.frame.maxY - screen.visibleFrame.maxY,
                                      leftArea: screen.auxiliaryTopLeftArea, rightArea: screen.auxiliaryTopRightArea,
                                      leftWidth: leftWidth, rightWidth: rightWidth)
        let cameraWidth = header.width - leftWidth - rightWidth
        let dashboardCenter = header.midX
        let minX = expanded ? min(header.minX, dashboardCenter - model.panelWidth / 2) : header.minX
        let maxX = expanded ? max(header.maxX, dashboardCenter + model.panelWidth / 2) : header.maxX
        let contentHeight = min(model.detailMetric == nil ? dashboardHeight : 588, min(600, max(120, header.minY - screen.visibleFrame.minY - 20)))
        if model.detailMetric != nil, model.detailHeight != max(100, contentHeight - 28) { model.detailHeight = max(100, contentHeight - 28) }
        dashboardFrame = NSRect(x: dashboardCenter - model.panelWidth / 2, y: header.minY - contentHeight, width: model.panelWidth, height: contentHeight)
        let width = maxX - minX
        let content = NotchContent(model: model, expanded: expanded, contentHeight: contentHeight,
                                                      headerHeight: header.height, cameraWidth: cameraWidth,
                                                      leftMetrics: leftMetrics, rightMetrics: rightMetrics,
                                                      leftWidth: leftWidth, rightWidth: rightWidth, panelWidth: width,
                                                      headerOffset: header.minX - minX, dashboardOffset: dashboardFrame.minX - minX,
                                                      toggle: { [weak self] in self?.toggle() },
                                                      select: { [weak self] id in
            guard let self else { return }
            if self.expanded && self.model.detailMetric == id { self.collapse() }
            else { self.model.openMetric(id); self.expand(resetPage: false) }
        },
                                                      measured: { [weak self] height in
            DispatchQueue.main.async {
                guard let self, self.expanded,
                      height.isFinite, abs(self.dashboardHeight - ceil(height)) > 0.5 else { return }
                self.dashboardHeight = ceil(height)
                self.update()
            }
        })
        if let hostingView {
            hostingView.rootView = content
        } else {
            let host = NSHostingView(rootView: content)
            host.sizingOptions = []
            hostingView = host
            panel.contentView = host
        }
        let height = header.height + (expanded ? contentHeight : 0)
        panel.setFrame(NSRect(x: minX, y: header.maxY - height, width: width, height: height), display: true)
        panel.orderFrontRegardless()
    }

    static func headerFrame(screen: NSRect, safeAreaTop: CGFloat, menuBarHeight: CGFloat,
                            leftArea: NSRect?, rightArea: NSRect?, leftWidth: CGFloat, rightWidth: CGFloat) -> NSRect {
        let height = safeAreaTop > 0 ? safeAreaTop : max(24, menuBarHeight)
        var cameraWidth: CGFloat = 0
        var center = screen.midX
        if safeAreaTop > 0 {
            if let leftArea, let rightArea {
                cameraWidth = max(0, rightArea.minX - leftArea.maxX)
                center = (leftArea.maxX + rightArea.minX) / 2
            } else {
                cameraWidth = 200
            }
        }
        let width = leftWidth + cameraWidth + rightWidth
        let x = cameraWidth > 0 ? center - cameraWidth / 2 - leftWidth : center - width / 2
        return NSRect(x: x, y: screen.maxY - height, width: width, height: height)
    }

    static func wingWidth(count: Int, fallback: Bool = false) -> CGFloat {
        if count == 0 { return fallback ? 26 : 0 }
        // Reserve only a percent cell per metric; changing readings must not make the notch jitter.
        return CGFloat(count) * 44 + CGFloat(count - 1) * 6 + 12
    }
}

private final class NotchPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

private struct NotchContent: View {
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject var model: AppModel
    let expanded: Bool
    let contentHeight: CGFloat
    let headerHeight: CGFloat
    let cameraWidth: CGFloat
    let leftMetrics: [String]
    let rightMetrics: [String]
    let leftWidth: CGFloat
    let rightWidth: CGFloat
    let panelWidth: CGFloat
    let headerOffset: CGFloat
    let dashboardOffset: CGFloat
    let toggle: () -> Void
    let select: (String) -> Void
    let measured: (CGFloat) -> Void
    var body: some View {
        ZStack(alignment: .topLeading) {
            HStack(spacing: 0) {
                    HStack(spacing: 6) {
                        if leftMetrics.isEmpty && rightMetrics.isEmpty {
                            Button(action: toggle) { MetricIcon(name: "glance").frame(width: 14, height: 14) }.buttonStyle(.plain).accessibilityIdentifier("glance-notch-toggle")
                        } else {
                            ForEach(leftMetrics, id: \.self) { metric($0) }
                        }
                    }.frame(width: leftWidth)
                    // The camera occupies this gap; no controls or padding are added to an unused wing.
                    Color.clear.frame(width: cameraWidth)
                    HStack(spacing: 6) {
                        ForEach(rightMetrics, id: \.self) { metric($0) }
                    }.frame(width: rightWidth)
                }.foregroundStyle(.white).frame(height: headerHeight)
                    .background(.black, in: UnevenRoundedRectangle(bottomLeadingRadius: 10, bottomTrailingRadius: 10))
                    .contentShape(Rectangle())
                    .environment(\.colorScheme, .dark)

                .offset(x: headerOffset)
            if expanded {
                Group {
                    if model.detailMetric != nil { Dashboard(model: model, power: model.power) }
                    else { ScrollView {
                    Dashboard(model: model, power: model.power)
                        .background(GeometryReader { proxy in
                            Color.clear.onAppear { measured(proxy.size.height) }
                                .onChange(of: proxy.size.height) { _, height in measured(height) }
                        })
                    } }
                }.scrollIndicators(.hidden).frame(width: model.panelWidth, height: contentHeight)
                    .background(Dashboard.background(for: colorScheme))
                    .clipShape(UnevenRoundedRectangle(bottomLeadingRadius: 14, bottomTrailingRadius: 14))
                    .offset(x: dashboardOffset, y: headerHeight)
            }
        }
        .frame(width: panelWidth, height: headerHeight + (expanded ? contentHeight : 0), alignment: .topLeading)
    }
    private func metric(_ id: String) -> some View {
        Button { select(id) } label: {
        HStack(spacing: 3) {
            MetricIcon(name: model.icon(for: id)).frame(width: 14, height: 14)
            Text(model.value(for: id)).font(.system(size: 10, weight: .medium)).monospacedDigit()
                .frame(width: 27, alignment: .trailing)
        }.contentShape(Rectangle())
        }.buttonStyle(.plain).accessibilityIdentifier("notch-metric-" + id)
            .accessibilityLabel("Open \(model.name(for: id)) details")
            .help("\(model.name(for: id)): \(model.value(for: id))")
    }
}
