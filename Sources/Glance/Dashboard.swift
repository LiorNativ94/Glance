import SwiftUI
import GlanceCore

struct Dashboard: View {
    static func background(for scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(red: 0.10, green: 0.105, blue: 0.115) : Color(red: 0.97, green: 0.97, blue: 0.975)
    }
    @ObservedObject var model: AppModel
    @ObservedObject var power: PowerController
    @AccessibilityFocusState private var overviewFocused: Bool
    @Environment(\.colorScheme) private var colorScheme
    var body: some View {
        VStack(spacing: 0) {
            if model.detailMetric == nil, let message = power.message ?? model.settingsError {
                HStack(alignment: .top, spacing: 8) {
                    Text(message).font(.system(size: 11)).fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                    Button {
                        power.message = nil; model.settingsError = nil
                    } label: { Image(systemName: "xmark") }
                        .buttonStyle(.plain).accessibilityLabel("Dismiss message")
                }.padding(10).background(.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
                    .padding(.bottom, 12).accessibilityIdentifier("dashboard-message")
            }
            switch model.page {
            case .overview: overview
            case .customize: customization
            case .settings: settings
            case .lidSetup: lidSetup
            case .subscriptions: subscriptionSettings
            case .dashboardLayout: dashboardLayout
            case .alerts: alertSettings
            case .alertDetail: alertDetail
            case .metric(let id): MetricDetails(model: model, id: id)
            }
        }
        .frame(width: model.panelWidth - 28)
        .padding(14)
        .fixedSize(horizontal: false, vertical: true)
        .background(Self.background(for: colorScheme))
        .tint(.blue)
        .onChange(of: model.page) { _, page in if page == .overview { overviewFocused = true } }
    }
    private var overview: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Glance").font(.system(size: 16, weight: .semibold))
                    .accessibilityIdentifier("glance-heading").accessibilityFocused($overviewFocused)
                Spacer()
                Circle().fill(.green).frame(width: 6, height: 6)
                Text("Live").font(.system(size: 10)).foregroundStyle(.secondary)
            }.padding(.bottom, 10)
            ForEach(model.visibleSections) { section in
                dashboardSection(section)
                line
            }
            if model.visibleSections.isEmpty {
                Text("Choose what appears here in Customize dashboard.")
                    .font(.system(size: 11)).foregroundStyle(.secondary).padding(.vertical, 12)
            }
            Button { model.page = .customize } label: {
                HStack(spacing: 8) {
                    symbol("slider.horizontal.3"); Text("Customize…").font(.system(size: 11))
                    Spacer(); Image(systemName: "chevron.right").font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary)
                }.contentShape(Rectangle())
            }.buttonStyle(.plain).accessibilityIdentifier("customize-menu-bar")
            line
            HStack {
                Button { model.page = .settings } label: { Label("Settings…", systemImage: "gearshape") }
                Spacer()
                Button("Activity Monitor") {
                    NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Utilities/Activity Monitor.app"))
                }
            }.buttonStyle(.plain).font(.system(size: 10)).foregroundStyle(.secondary)
        }
    }
    @ViewBuilder private func dashboardSection(_ section: DashboardSection) -> some View {
        switch section {
        case .system: systemSection
        case .storage: storageSection
        case .awake: awakeSection
        case .subscriptions: subscriptionSection
        }
    }
    private var systemSection: some View {
        VStack(spacing: 0) {
            Button { model.openMetric("cpu") } label: {
                metricRow("CPU", icon: "cpu", value: ReadingFormat.percent(model.snapshot.cpu), history: model.cpuHistory)
            }.buttonStyle(.plain).accessibilityIdentifier("overview-cpu")
            Button { model.openMetric("memory") } label: {
            metricRow("Memory", icon: "memorychip",
                      value: ReadingFormat.memory(model.snapshot.memoryUsed, total: model.snapshot.memoryTotal),
                      history: model.memoryHistory)
            }.buttonStyle(.plain).accessibilityIdentifier("overview-memory")
        }
    }
    private var storageSection: some View {
        VStack(spacing: 0) {
            HStack { Text("Storage").font(.system(size: 12, weight: .semibold)).foregroundStyle(.secondary); Spacer() }
                .padding(.bottom, 9)
            ScrollView {
                VStack(spacing: 10) {
                    ForEach(model.snapshot.volumes) { volume in storageRow(volume) }
                    if model.snapshot.volumes.isEmpty { Text("Reading connected storage…").foregroundStyle(.secondary) }
                }
            }.scrollIndicators(.hidden)
                .frame(height: CGFloat(max(1, min(model.snapshot.volumes.count, 3))) * 47 - 3)
        }
    }
    private var awakeSection: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 8) {
                symbol("cup.and.saucer").padding(.top, 3)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Keep awake").font(.system(size: 12, weight: .medium))
                    Text(power.remaining).font(.system(size: 10)).foregroundStyle(.secondary)
                }
                Spacer()
                Toggle("Keep awake", isOn: Binding(get: { power.active }, set: power.setActive))
                    .labelsHidden().toggleStyle(.switch).controlSize(.small)
                    .accessibilityIdentifier("keep-awake")
            }
            if power.active {
                Picker("Duration", selection: Binding(get: { power.duration }, set: power.selectDuration)) {
                    Text("30m").tag(30); Text("1h").tag(60); Text("2h").tag(120); Text("Until off").tag(0)
                }.pickerStyle(.segmented).padding(.top, 12).padding(.leading, 28)
                if power.deadline != nil {
                    HStack(spacing: 8) {
                        Button("+15m") { power.extendSession(by: 15) }.accessibilityIdentifier("extend-awake-15")
                        Button("+30m") { power.extendSession(by: 30) }.accessibilityIdentifier("extend-awake-30")
                        Spacer()
                        Button("Stop") { power.stop() }
                    }.font(.system(size: 11)).padding(.top, 10).padding(.leading, 28)
                }
                Toggle("Keep display on", isOn: Binding(get: { power.displayOn }, set: power.setDisplay))
                    .toggleStyle(.checkbox).font(.system(size: 11)).padding(.top, 10)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(.leading, 28)
            }
            if power.lidActive || power.lidStopping || power.authorizing { lidControl }
        }
    }
    private var subscriptionSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button { model.page = .subscriptions } label: {
                HStack {
                    Label("AI subscriptions", systemImage: "sparkles")
                    Spacer(); Image(systemName: "chevron.right")
                }.font(.system(size: 11, weight: .medium)).contentShape(Rectangle())
            }.buttonStyle(.plain).accessibilityIdentifier("subscriptions")
            if model.subscriptions.enabled.isEmpty {
                Text("Add Claude or Codex usage").font(.system(size: 10)).foregroundStyle(.secondary)
            }
            ForEach(SubscriptionProvider.allCases.filter { model.subscriptions.enabled.contains($0) }) { provider in
                Button { model.openMetric(provider.rawValue) } label: {
                    HStack(spacing: 8) {
                        MetricIcon(name: "\(provider.rawValue)-usage").frame(width: 14, height: 14)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(provider.name)
                            if let window = model.subscriptions.states[provider]?.usage?.limitingWindow() {
                                Text("\(window.title) · \(window.resetDescription())").foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        Text(ReadingFormat.percent(model.subscriptions.remaining(provider)) + " left").monospacedDigit()
                        Image(systemName: "chevron.right").foregroundStyle(.secondary)
                    }.font(.system(size: 10)).contentShape(Rectangle())
                }.buttonStyle(.plain).accessibilityIdentifier("overview-" + provider.rawValue)
            }
        }
    }
    private var lidControl: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                symbol("laptopcomputer")
                VStack(alignment: .leading, spacing: 3) {
                    Text("Lid-closed mode").font(.system(size: 11))
                    Text(power.lidStopping ? "Restoring normal sleep…" : power.lidActive ? "Active for this session" : power.authorizing ? "Waiting for authorization…" : "Optional")
                        .font(.system(size: 10)).foregroundStyle(.secondary)
                }
                Spacer()
                if power.lidActive {
                    Button("Stop") { power.endLidSession() }.disabled(power.lidStopping)
                } else {
                    Button("Set up") { model.page = .lidSetup }.disabled(power.authorizing || power.lidStopping)
                }
            }.padding(.top, 12)
        }
    }
    private var displayMode: some View {
        HStack(spacing: 10) {
            Text("Show in").font(.system(size: 11)).foregroundStyle(.secondary)
            Picker("Show in", selection: $model.showInNotch) {
                Text("Menu bar").tag(false)
                Text("Notch").tag(true)
            }.labelsHidden().pickerStyle(.segmented).accessibilityIdentifier("display-mode")
        }.padding(.bottom, 12)
    }
    private var customization: some View {
        VStack(alignment: .leading, spacing: 12) {
            pageHeader("Customize")
            displayMode
            Button("Customize dashboard…") { model.page = .dashboardLayout }
                .accessibilityIdentifier("customize-dashboard")
            Text("Choose the icons shown in the menu bar or notch.")
                .font(.system(size: 10)).foregroundStyle(.secondary)
            ScrollView {
                VStack(spacing: 12) {
                    ForEach(model.metricChoices, id: \.id) { metric in
                        HStack(spacing: 8) {
                            symbol(metric.icon); Text(metric.name).font(.system(size: 11)).lineLimit(1)
                            Spacer()
                            Toggle(metric.name, isOn: Binding(get: { model.selected.contains(metric.id) },
                                                              set: { model.setSelected(metric.id, enabled: $0) }))
                                .labelsHidden().toggleStyle(.checkbox)
                                .accessibilityIdentifier("select-\(metric.id)")
                        }
                    }
                }.padding(10)
            }.frame(height: CGFloat(min(model.metricChoices.count, 7)) * 32 + 8)
                .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 12))
            Toggle("Show keep-awake icon", isOn: $model.showAwakeIcon)
                .toggleStyle(.checkbox).font(.system(size: 11))
            Divider()
            Text("Preview").font(.system(size: 12, weight: .semibold))
            HStack(spacing: 8) {
                Spacer(minLength: 0)
                if model.visibleMetrics.isEmpty {
                    MetricIcon(name: "glance").frame(width: 18, height: 18)
                } else {
                    ForEach(model.visibleMetrics, id: \.self) { id in
                        HStack(spacing: 4) {
                            MetricIcon(name: model.icon(for: id)).frame(width: 14, height: 14); Text(model.value(for: id)).monospacedDigit()
                        }.font(.system(size: 11))
                    }
                }
                if model.showAwakeIcon && power.active { Image(systemName: "cup.and.saucer") }
                Spacer(minLength: 0)
            }.padding(14).frame(maxWidth: .infinity)
                .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 10))
            Text("None selected? The Glance icon stays visible.")
                .font(.system(size: 10)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            HStack { Spacer(); Button("Done") { model.page = .overview }.buttonStyle(.borderedProminent) }
        }
    }
    private var settings: some View {
        VStack(alignment: .leading, spacing: 14) {
            pageHeader("Settings")
            HStack(spacing: 10) {
                Image(nsImage: NSImage(named: "GlanceIcon") ?? MetricIcons.image("glance"))
                    .resizable().frame(width: 44, height: 44)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Glance").font(.system(size: 18, weight: .semibold))
                    Text("Your Mac, at a glance.").font(.system(size: 10)).foregroundStyle(.secondary)
                }
            }
            displayMode
            HStack(spacing: 10) {
                Text("Appearance").font(.system(size: 11)).foregroundStyle(.secondary)
                Picker("Appearance", selection: $model.appearance) {
                    ForEach(AppModel.Appearance.allCases, id: \.self) { appearance in
                        Text(appearance.title).tag(appearance)
                    }
                }.labelsHidden().pickerStyle(.segmented).accessibilityIdentifier("dashboard-appearance")
            }
            Toggle("Open Glance at login", isOn: Binding(get: { model.launchAtLogin }, set: model.setLogin))
                .toggleStyle(.checkbox)
            Text("Notch mode sits beside the camera, or at the center of displays without a notch.")
                .font(.system(size: 10)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            Button("Claude & Codex subscriptions…") { model.page = .subscriptions }
            Button("Alerts…") { model.page = .alerts }.accessibilityIdentifier("alert-settings")
            lidControl
            Text("Readings update every 2 seconds. Storage refreshes every 15 seconds and when drives connect or disconnect.")
                .font(.system(size: 10)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            Text("Keep-awake stops at 10% battery. Lid-closed mode is temporary and needs authorization for each session.")
                .font(.system(size: 10)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            Divider()
            HStack {
                Text("Version \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Development")")
                    .font(.system(size: 10)).foregroundStyle(.secondary)
                Spacer()
                Button("Quit Glance") { NSApplication.shared.terminate(nil) }
            }
        }
    }
    private var dashboardLayout: some View {
        VStack(alignment: .leading, spacing: 14) {
            pageHeader("Customize dashboard")
            Text("Show the sections you use, in your preferred order.")
                .font(.system(size: 11)).foregroundStyle(.secondary)
            ForEach(model.sectionOrder) { section in
                HStack(spacing: 8) {
                    Toggle(section.title, isOn: Binding(get: { !model.hiddenSections.contains(section) }, set: { shown in
                        if shown { model.hiddenSections.remove(section) } else { model.hiddenSections.insert(section) }
                    })).toggleStyle(.checkbox).font(.system(size: 11))
                        .accessibilityIdentifier("section-\(section.rawValue)")
                    Spacer()
                    Button { model.moveSection(section, by: -1) } label: { Image(systemName: "chevron.up") }
                        .disabled(model.sectionOrder.first == section).accessibilityLabel("Move \(section.title) up")
                        .accessibilityIdentifier("move-up-\(section.rawValue)")
                    Button { model.moveSection(section, by: 1) } label: { Image(systemName: "chevron.down") }
                        .disabled(model.sectionOrder.last == section).accessibilityLabel("Move \(section.title) down")
                        .accessibilityIdentifier("move-down-\(section.rawValue)")
                }
            }
            Text("Active keep-awake sessions stay visible. Icon choices are separate.")
                .font(.system(size: 10)).foregroundStyle(.secondary)
            HStack {
                Button("Restore defaults") { model.sectionOrder = DashboardSection.allCases; model.hiddenSections = [] }
                Spacer()
                Button("Done") { model.page = .overview }.buttonStyle(.borderedProminent)
            }
        }
    }
    private var alertSettings: some View {
        VStack(alignment: .leading, spacing: 14) {
            pageHeader("Alerts")
            Text("Optional notifications, once per condition while Glance is running. No sounds.")
                .font(.system(size: 11)).foregroundStyle(.secondary)
            ForEach(AlertKind.allCases) { kind in
                VStack(alignment: .leading, spacing: 5) {
                    HStack {
                        Text(kind.title).font(.system(size: 12, weight: .medium))
                        Spacer()
                        Toggle(kind.title, isOn: Binding(get: { model.enabledAlerts.contains(kind) },
                                                        set: { model.setAlertEnabled(kind, $0) }))
                            .labelsHidden().toggleStyle(.switch).controlSize(.small).disabled(model.pendingAlerts.contains(kind))
                            .accessibilityIdentifier("alert-\(kind.rawValue)")
                    }
                    switch kind {
                    case .ai:
                        Stepper("At or below \(model.alertThresholds.aiRemainingPercent)% remaining", value: Binding(
                            get: { model.alertThresholds.aiRemainingPercent }, set: { model.updateAlertThresholds(ai: $0) }), in: 1...100)
                            .font(.system(size: 11)).accessibilityIdentifier("alert-ai-threshold")
                        Text("Applies to Claude and Codex. For example, 20% remaining means 80% used.")
                            .font(.system(size: 10)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    case .memory:
                        Text("When macOS reports elevated pressure for one minute. This measures pressure, not a percentage of RAM used.")
                            .font(.system(size: 10)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    case .storage:
                        Stepper("Below \(model.alertThresholds.storageFreePercent)% free", value: Binding(
                            get: { model.alertThresholds.storageFreePercent }, set: { model.updateAlertThresholds(storagePercent: $0) }), in: 1...100)
                            .font(.system(size: 11)).accessibilityIdentifier("alert-storage-percent")
                        Stepper("And below \(model.alertThresholds.storageFreeGB) GB free", value: Binding(
                            get: { model.alertThresholds.storageFreeGB }, set: { model.updateAlertThresholds(storageGB: $0) }), in: 1...1000)
                            .font(.system(size: 11)).accessibilityIdentifier("alert-storage-gb")
                    }
                }
            }
            Text("AI alerts use fresh provider readings, refreshed every 5 minutes. Stale or unavailable readings never trigger an alert.")
                .font(.system(size: 10)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            Button("Notification settings…") {
                NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension")!)
            }.font(.system(size: 11))
        }
    }
    private var alertDetail: some View {
        VStack(alignment: .leading, spacing: 12) {
            pageHeader(model.alertToReview?.kind.title ?? "Alert")
            if let alert = model.alertToReview {
                Text("Earlier alert: \(alert.body)").font(.system(size: 11)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Current readings").font(.system(size: 12, weight: .medium))
                if alert.kind == .memory {
                    systemSection
                    Text(model.memoryPressure ? "Memory pressure is elevated" : "No elevated memory pressure reported")
                        .font(.system(size: 11))
                    Button("Open Activity Monitor") {
                        NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Utilities/Activity Monitor.app"))
                    }
                } else { storageSection }
            }
        }
    }
    private var subscriptionSettings: some View {
        VStack(alignment: .leading, spacing: 12) {
            pageHeader("AI subscriptions")
            Text("Connect existing Claude Code and Codex sign-ins to see your plan’s usage limits.")
                .font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            ScrollView {
                SubscriptionCards(store: model.subscriptions, openDetails: { model.openMetric($0.rawValue) })
            }.scrollIndicators(.hidden).frame(height: 380)
            Text("Updates every 5 minutes. Menu bar percentages show the lowest remaining limit. Add them in Customize…")
                .font(.system(size: 10)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }
    private var lidSetup: some View {
        VStack(alignment: .leading, spacing: 12) {
            pageHeader("Keep working with the lid closed")
            Image(systemName: "laptopcomputer").font(.system(size: 34)).foregroundStyle(.blue)
            Text("For downloads and background work when your MacBook is closed.")
                .font(.system(size: 12, weight: .medium)).fixedSize(horizontal: false, vertical: true)
            Text("Glance temporarily disables system sleep, including the Apple menu’s Sleep command. macOS will ask for administrator authorization.")
                .font(.system(size: 11)).fixedSize(horizontal: false, vertical: true)
            Text("Normal sleep returns when this session ends, Glance quits, or the battery reaches 10%. A helper also restores sleep if Glance stops responding.")
                .font(.system(size: 11)).fixedSize(horizontal: false, vertical: true)
            Text("Keep the Mac ventilated. Try a short session on your setup first; closed-lid behavior can vary with macOS and hardware.")
                .font(.system(size: 10)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            HStack {
                Button("Cancel") { model.page = .overview }
                Spacer()
                Button("Enable for this session") { model.page = .overview; power.startLidSession() }
                    .buttonStyle(.borderedProminent)
            }
        }
    }
    private func pageHeader(_ text: String) -> some View {
        HStack(alignment: .center, spacing: 10) {
            Button { model.page = .overview } label: { Image(systemName: "chevron.left") }
                .buttonStyle(.plain).accessibilityLabel("Back to overview")
            Text(text).font(.system(size: 15, weight: .semibold))
            Spacer(minLength: 0)
        }
    }
    private func symbol(_ name: String) -> some View {
        MetricIcon(name: name).frame(width: 18, height: 18).foregroundStyle(.primary.opacity(0.8))
    }
    private var line: some View { Divider().padding(.vertical, 10) }
    private func metricRow(_ title: String, icon: String, value: String, history: [Double]) -> some View {
        HStack(spacing: 8) {
            symbol(icon)
            Text(title).font(.system(size: 11)).frame(width: 44, alignment: .leading)
            Sparkline(values: history).frame(width: 64, height: 20)
            Spacer(minLength: 8)
            Text(value).font(.system(size: 10, weight: .medium)).monospacedDigit().lineLimit(1)
        }.padding(.vertical, 5)
    }
    private func storageRow(_ volume: StorageVolume) -> some View {
        HStack(alignment: .center, spacing: 8) {
            symbol(volume.isInternal ? "internaldrive" : "externaldrive")
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(volume.name).font(.system(size: 11, weight: .medium)).lineLimit(1).truncationMode(.middle)
                    Spacer(minLength: 8)
                    Text("\(ReadingFormat.bytes(volume.used)) / \(ReadingFormat.bytes(volume.total))")
                        .font(.system(size: 10)).foregroundStyle(.secondary).monospacedDigit()
                }
                GeometryReader { proxy in
                    Capsule().fill(.quaternary)
                        .overlay(alignment: .leading) {
                            Capsule().fill(volume.fraction > 0.95 ? Color.orange : Color.secondary.opacity(0.6))
                                .frame(width: max(0, proxy.size.width * volume.fraction))
                        }
                }.frame(height: 5)
                HStack {
                    Text(volume.isInternal ? "Internal" : "External")
                    Spacer()
                    Text("\(ReadingFormat.bytes(volume.available)) free")
                }.font(.system(size: 10)).foregroundStyle(.secondary)
            }
        }.help(volume.path)
    }
}

struct Sparkline: View {
    let values: [Double]
    var body: some View {
        Canvas { context, size in
            guard values.count >= 2 else { return }
            var line = Path()
            for (index, value) in values.enumerated() {
                let point = CGPoint(x: size.width * Double(index) / Double(values.count - 1),
                                    y: 2 + (size.height - 4) * (1 - min(1, max(0, value))))
                if index == 0 { line.move(to: point) } else { line.addLine(to: point) }
            }
            var fill = line
            fill.addLine(to: CGPoint(x: size.width, y: size.height)); fill.addLine(to: CGPoint(x: 0, y: size.height)); fill.closeSubpath()
            context.fill(fill, with: .linearGradient(Gradient(colors: [.blue.opacity(0.16), .blue.opacity(0)]),
                                                     startPoint: .zero, endPoint: CGPoint(x: 0, y: size.height)))
            context.stroke(line, with: .color(.blue), style: StrokeStyle(lineWidth: 1.4, lineCap: .round, lineJoin: .round))
        }.accessibilityHidden(true)
    }
}
