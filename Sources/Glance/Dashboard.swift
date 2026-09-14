import SwiftUI
import GlanceCore

struct Dashboard: View {
    @ObservedObject var model: AppModel
    @ObservedObject var power: PowerController
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Text("Show in").font(.system(size: 11)).foregroundStyle(.secondary)
                Picker("Show in", selection: $model.showInNotch) {
                    Text("Menu bar").tag(false)
                    Text("Notch").tag(true)
                }.labelsHidden().pickerStyle(.segmented).accessibilityIdentifier("display-mode")
            }.padding(.bottom, 12)
            switch model.page {
            case .overview: overview
            case .customize: customization
            case .settings: settings
            case .lidSetup: lidSetup
            case .subscriptions: subscriptionSettings
            }
        }
        .frame(width: 292)
        .padding(14)
        .fixedSize(horizontal: false, vertical: true)
        .background(.regularMaterial)
        .tint(.blue)
        .alert("Glance", isPresented: Binding(get: { power.message != nil || model.settingsError != nil },
                                               set: { if !$0 { power.message = nil; model.settingsError = nil } })) {
            Button("OK") { power.message = nil; model.settingsError = nil }
        } message: { Text(power.message ?? model.settingsError ?? "") }
    }
    private var overview: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Glance").font(.system(size: 16, weight: .semibold))
                Spacer()
                Circle().fill(.green).frame(width: 6, height: 6)
                Text("Live").font(.system(size: 10)).foregroundStyle(.secondary)
            }.padding(.bottom, 10)
            metricRow("CPU", icon: "cpu", value: ReadingFormat.percent(model.snapshot.cpu), history: model.cpuHistory)
            metricRow("Memory", icon: "memorychip",
                      value: ReadingFormat.memory(model.snapshot.memoryUsed, total: model.snapshot.memoryTotal),
                      history: model.memoryHistory)
            line
            HStack { Text("Storage").font(.system(size: 12, weight: .semibold)).foregroundStyle(.secondary); Spacer() }
                .padding(.bottom, 9)
            ScrollView {
                VStack(spacing: 10) {
                    ForEach(model.snapshot.volumes) { volume in storageRow(volume) }
                    if model.snapshot.volumes.isEmpty { Text("Reading connected storage…").foregroundStyle(.secondary) }
                }
            }.scrollIndicators(.hidden)
                .frame(height: CGFloat(max(1, min(model.snapshot.volumes.count, 3))) * 47 - 3)
            if let battery = model.snapshot.battery {
                line
                HStack(spacing: 8) {
                    symbol("battery.100")
                    Text("Battery")
                    Spacer()
                    Text("\(ReadingFormat.percent(battery.fraction)) · \(battery.detail)").foregroundStyle(.secondary)
                }.font(.system(size: 11))
            }
            line
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
                Toggle("Keep display on", isOn: Binding(get: { power.displayOn }, set: power.setDisplay))
                    .toggleStyle(.checkbox).font(.system(size: 11)).padding(.top, 10)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(.leading, 28)
            }
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
            line
            Button { model.page = .subscriptions } label: {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Label("AI subscriptions", systemImage: "sparkles").font(.system(size: 11, weight: .medium))
                        Spacer()
                        Image(systemName: "chevron.right").font(.system(size: 10)).foregroundStyle(.secondary)
                    }
                    if model.subscriptions.enabled.isEmpty {
                        Text("Add Claude or Codex usage").font(.system(size: 10)).foregroundStyle(.secondary)
                    } else {
                        ForEach(SubscriptionProvider.allCases.filter { model.subscriptions.enabled.contains($0) }) { provider in
                            HStack {
                                MetricIcon(name: "\(provider.rawValue)-usage").frame(width: 12, height: 12)
                                Text(provider.name)
                                Spacer()
                                if let remaining = model.subscriptions.remaining(provider) {
                                    Text("\(ReadingFormat.percent(remaining)) left")
                                } else {
                                    Text(model.subscriptions.states[provider]?.refreshing == true ? "Refreshing…" : "Open for details")
                                }
                            }.font(.system(size: 10)).foregroundStyle(.secondary)
                        }
                    }
                }.contentShape(Rectangle())
            }.buttonStyle(.plain).accessibilityIdentifier("subscriptions")
            line
            Button { model.page = .customize } label: {
                HStack(spacing: 8) {
                    symbol("slider.horizontal.3"); Text("Icons…").font(.system(size: 11))
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
    private var customization: some View {
        VStack(alignment: .leading, spacing: 12) {
            pageHeader("Customize icons")
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
            Toggle("Open Glance at login", isOn: Binding(get: { model.launchAtLogin }, set: model.setLogin))
                .toggleStyle(.checkbox)
            Text("Choose Menu bar or Notch above. Notch mode sits beside the camera; click it to open Glance. Displays without a notch use the center of the menu-bar row.")
                .font(.system(size: 10)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            Button("Claude & Codex subscriptions…") { model.page = .subscriptions }
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
    private var subscriptionSettings: some View {
        VStack(alignment: .leading, spacing: 12) {
            pageHeader("AI subscriptions")
            Text("Connect existing Claude Code and Codex sign-ins to see your plan’s usage limits.")
                .font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            ScrollView {
                SubscriptionCards(store: model.subscriptions)
            }.scrollIndicators(.hidden).frame(height: 380)
            Text("Updates every 5 minutes. Menu bar percentages show the lowest remaining limit. Add them in Icons…")
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
