import SwiftUI
import Charts
import GlanceCore

struct SubscriptionDetails: View {
    let model: AppModel
    @ObservedObject var store: SubscriptionStore
    @ObservedObject var history: QuotaHistoryStore
    @ObservedObject var activity: LocalActivityStore
    @ObservedObject var sessions: AgentSessionStore
    let provider: SubscriptionProvider
    @State private var tab = "Summary"
    @State private var days = 7
    @State private var grouping = "Model"
    @State private var selectedWindow = ""
    @State private var selectedPeriod: UUID?
    @State private var showLimits = false
    private var state: SubscriptionStore.State { store.states[provider] ?? .init() }
    private var usage: SubscriptionUsage? { state.usage }
    private var weekly: UsageWindow? {
        usage?.windows.first { $0.isGeneral && ($0.durationSeconds == 604800 || ["seven_day", "secondary_window"].contains($0.id)) }
    }
    private var periods: [QuotaPeriod] {
        history.history.periods(provider: provider, account: usage?.accountID, window: selectedWindow.isEmpty ? (weekly?.id ?? "") : selectedWindow, plan: usage?.plan ?? "Unknown plan")
    }
    private var since: Date {
        Calendar.current.date(byAdding: .day, value: 1 - days, to: Calendar.current.startOfDay(for: .now))!
    }
    private var report: LocalActivityReport? { activity.reports[provider] }
    private var tint: Color { .accentColor }
    private let tabs = ["Summary", "Sessions", "Activity", "History"]

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { _ in content }
    }
    private var content: some View {
        VStack(spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(usage?.plan?.replacingOccurrences(of: "_", with: " ").capitalized ?? "Subscription").font(.system(size: 12, weight: .medium))
                    if let updated = usage?.updatedAt {
                        Text("Updated \(updated.formatted(date: .omitted, time: .shortened))").font(.system(size: 11)).foregroundStyle(.secondary)
                    } else { Text("Account allowance").font(.system(size: 11)).foregroundStyle(.secondary) }
                }
                Spacer()
                Button(state.refreshing ? "Refreshing…" : "Refresh") {
                    store.refresh(provider, allowInteraction: true)
                    activity.refresh(provider)
                }.buttonStyle(.plain).foregroundStyle(.blue).font(.system(size: 11)).disabled(state.refreshing)
                    .accessibilityIdentifier("refresh-" + provider.rawValue)
            }
            Picker("Usage view", selection: $tab) {
                ForEach(tabs, id: \.self) { Text($0).tag($0) }
            }.pickerStyle(.segmented).labelsHidden().accessibilityIdentifier("usage-tabs")
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if !store.enabled.contains(provider) && tab != "Sessions" { connection }
                    else {
                        if tab != "Sessions", let error = state.error { note(error, warning: true) }
                        if tab != "Sessions", let usage, Date.now.timeIntervalSince(usage.updatedAt) >= 600 {
                            note("Last known allowance. Refresh to see current availability.", warning: true)
                        }
                        switch tab {
                        case "Sessions": sessionsContent
                        case "Activity": activityContent
                        case "History": historyContent
                        default: summary
                        }
                    }
                }.frame(maxWidth: .infinity, alignment: .leading).padding(.bottom, 4)
            }.scrollIndicators(.automatic)
            HStack {
                if tab == "Sessions" {
                    Button("Session alerts…") { model.page = .alerts }
                } else {
                    Button("Open usage page ↗") { NSWorkspace.shared.open(provider.usageURL) }
                }
                Spacer()
            }.buttonStyle(.plain).font(.system(size: 11)).foregroundStyle(.blue)
        }
        .disclosureGroupStyle(FullRowDisclosureStyle())
        .onAppear {
            tab = tabs.contains(model.providerTabs[provider] ?? "") ? model.providerTabs[provider]! : "Summary"
            sessions.refresh()
        }
        .onChange(of: tab) { _, value in model.providerTabs[provider] = value }
        .onChange(of: usage?.accountID) { _, _ in selectedWindow = ""; selectedPeriod = nil }
    }

    private var connection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Connect \(provider.name)").font(.system(size: 16, weight: .semibold))
            note(provider.signInHelp)
            Button("Use existing sign-in") { store.setEnabled(provider, true) }.buttonStyle(.borderedProminent)
        }.padding(.vertical, 12)
    }
    private var summary: some View {
        Group {
            if let usage {
                let primary = usage.limitingWindow() ?? usage.windows.filter(\.isGeneral).min { $0.remainingFraction < $1.remainingFraction }
                if let primary {
                    allowanceHero(primary, current: usage.limitingWindow() != nil)
                    ForEach(usage.windows.filter { $0.isGeneral && $0.id != primary.id }) { allowance($0) }
                }
                if usage.windows.isEmpty { note("This account did not report any allowance windows.") }
                if usage.windows.contains(where: { !$0.isGeneral }) {
                    DisclosureGroup("Model & feature limits", isExpanded: $showLimits) {
                        VStack(spacing: 14) { ForEach(usage.windows.filter { !$0.isGeneral }) { allowance($0) } }.padding(.top, 10)
                    }.font(.system(size: 12, weight: .medium))
                }
                if provider == .codex {
                    Divider()
                    resetInventory
                }
                Divider()
                Button { tab = "History" } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Quota history").font(.system(size: 12, weight: .medium)).foregroundStyle(.primary)
                            Text(history.enabled ? "View observed changes" : "Track allowance changes on this Mac")
                                .font(.system(size: 11)).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right").font(.system(size: 11)).foregroundStyle(.secondary)
                    }.padding(.vertical, 4).contentShape(Rectangle())
                }.buttonStyle(.plain).accessibilityIdentifier("view-quota-history")
            } else if state.refreshing { ProgressView("Reading allowance…").controlSize(.small) }
        }
    }
    private func allowanceHero(_ window: UsageWindow, current: Bool) -> some View {
        let color = current ? SubscriptionPresentation.allowanceColor(window) : Color.secondary
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(window.title + " allowance").font(.system(size: 12, weight: .medium))
                Spacer()
                if current && window.usedPercent >= 80 {
                    Label(window.usedPercent >= 90 ? "Very low" : "Low", systemImage: "exclamationmark.circle.fill")
                        .font(.system(size: 11, weight: .medium)).foregroundStyle(color)
                }
            }
            HStack(alignment: .firstTextBaseline, spacing: 7) {
                Text("\(100 - window.usedPercent, specifier: "%.0f")%")
                    .font(.system(size: 36, weight: .semibold)).monospacedDigit()
                Text(current ? "remaining" : "last known remaining")
                    .font(.system(size: 12)).foregroundStyle(.secondary)
            }
            ProgressView(value: window.usedPercent, total: 100).tint(color)
            Text(window.resetDescription()).font(.system(size: 12)).foregroundStyle(.secondary)
                .help(window.resetsAt?.formatted(date: .complete, time: .shortened) ?? "Reset time unavailable")
        }.padding(14).frame(maxWidth: .infinity, alignment: .leading)
            .background(color.opacity(0.07), in: RoundedRectangle(cornerRadius: 12))
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("primary-allowance")
    }
    private func allowance(_ window: UsageWindow) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(window.title).fontWeight(.medium)
                Spacer()
                Text("\(100 - window.usedPercent, specifier: "%.0f")% left").monospacedDigit().fontWeight(.semibold)
            }.font(.system(size: 12))
            ProgressView(value: window.usedPercent, total: 100).tint(SubscriptionPresentation.allowanceColor(window))
            Text(window.resetDescription()).font(.system(size: 11)).foregroundStyle(.secondary)
                .help(window.resetsAt?.formatted(date: .complete, time: .shortened) ?? "Reset time unavailable")
        }.accessibilityElement(children: .combine)
    }
    private var resetInventory: some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionTitle("Usage resets")
            if let inventory = state.resetInventory {
                Text("\(inventory.count()) available").font(.system(size: 15, weight: .semibold))
                if let expiry = inventory.availableCredits().compactMap(\.expiresAt).min() {
                    note("Next expiry: \(expiry.formatted(date: .abbreviated, time: .shortened))")
                }
                Text("Checked \(inventory.updatedAt.formatted(date: .omitted, time: .shortened))")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
            } else { note(state.resetRefreshing ? "Checking available resets…" : (state.resetError ?? "Reset inventory was not supplied for this account.")) }
        }
    }
    private var sessionsContent: some View {
        Group {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("\(sessions.activeCount) active agent\(sessions.activeCount == 1 ? "" : "s")")
                        .font(.system(size: 22, weight: .semibold)).monospacedDigit()
                    Text(provider == .claude ? "Open Claude Code sessions on this Mac" : "Local Codex tasks from the last 24 hours")
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                }
                Spacer()
                if sessions.attentionCount > 0 {
                    Label("\(sessions.attentionCount) needs you", systemImage: "exclamationmark.circle.fill")
                        .font(.system(size: 11, weight: .medium)).foregroundStyle(.orange)
                }
            }
            if let error = sessions.snapshot.error { note(error, warning: true) }
            if sessions.sessions.isEmpty && sessions.snapshot.error == nil {
                note(provider == .claude ? "No open Claude Code sessions. Sessions appear here while they are open in Claude or a terminal."
                     : "No recent Codex tasks found. New tasks appear here automatically while Glance is running.")
            }
            ForEach(groupedSessions, id: \.project) { group in
                VStack(alignment: .leading, spacing: 0) {
                    HStack {
                        Text(group.project).font(.system(size: 12, weight: .semibold))
                        Spacer()
                        Text("\(group.sessions.count)").font(.system(size: 10)).foregroundStyle(.secondary).monospacedDigit()
                    }.padding(.bottom, 4)
                    ForEach(group.sessions) { session in sessionRow(session) }
                }
            }
            note(provider == .claude ? "Glance reads session status only; prompts and responses are not read. Click a session to open it in Claude."
                 : "Glance stores lifecycle metadata only; prompts and responses are not retained. Click a task to open it in Codex.")
        }
    }
    private var groupedSessions: [(project: String, sessions: [AgentSession])] {
        Self.groupedSessions(sessions.sessions)
    }
    static func groupedSessions(_ sessions: [AgentSession]) -> [(project: String, sessions: [AgentSession])] {
        Dictionary(grouping: sessions, by: \.project).map { project, values in
            (project, values.sorted {
                $0.updatedAt == $1.updatedAt
                    ? $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
                    : $0.updatedAt > $1.updatedAt
            })
        }.sorted {
            let left = $0.sessions.map(\.updatedAt).max() ?? .distantPast
            let right = $1.sessions.map(\.updatedAt).max() ?? .distantPast
            return left == right ? $0.project.localizedCaseInsensitiveCompare($1.project) == .orderedAscending : left > right
        }
    }
    private func sessionRow(_ session: AgentSession) -> some View {
        VStack(spacing: 0) {
            Button {
                if let url = session.deepLink { NSWorkspace.shared.open(url) }
            } label: {
                HStack(spacing: 9) {
                    Image(systemName: sessionIcon(session.status))
                        .foregroundStyle(sessionColor(session.status)).frame(width: 14)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(session.title).font(.system(size: 11, weight: .medium)).lineLimit(1)
                        HStack(spacing: 4) {
                            if let agent = session.agentName, agent != session.title { Text(agent); Text("·") }
                            Text(sessionStatus(session.status))
                            Text("·")
                            Text(sessionTime(session))
                        }.font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1)
                    }
                    Spacer(minLength: 6)
                    if session.deepLink != nil {
                        Image(systemName: "arrow.up.forward.app").font(.system(size: 10)).foregroundStyle(.secondary)
                    }
                }.padding(.vertical, 8).contentShape(Rectangle())
            }.buttonStyle(.plain).allowsHitTesting(session.deepLink != nil)
                .accessibilityIdentifier("\(provider.rawValue)-session-\(session.id)")
            Divider()
        }
    }
    private func sessionStatus(_ status: AgentSessionStatus) -> String {
        switch status {
        case .running: return "Running"
        case .needsInput: return "Needs input"
        case .needsApproval: return "Needs approval"
        case .ready: return "Ready"
        case .failed: return "Error"
        }
    }
    private func sessionIcon(_ status: AgentSessionStatus) -> String {
        switch status {
        case .running: return "circle.fill"
        case .needsInput, .needsApproval: return "exclamationmark.circle.fill"
        case .ready: return "checkmark.circle.fill"
        case .failed: return "xmark.circle.fill"
        }
    }
    private func sessionColor(_ status: AgentSessionStatus) -> Color {
        switch status {
        case .running: return .blue
        case .needsInput, .needsApproval: return .orange
        case .ready: return .green
        case .failed: return .red
        }
    }
    private func sessionTime(_ session: AgentSession) -> String {
        if session.status.isActive, let started = session.startedAt {
            let seconds = max(0, Int(Date.now.timeIntervalSince(started)))
            if seconds < 60 { return "\(seconds)s" }
            if seconds < 3600 { return "\(seconds / 60)m" }
            return "\(seconds / 3600)h \((seconds % 3600) / 60)m"
        }
        return session.updatedAt.formatted(.relative(presentation: .named))
    }
    private var activityContent: some View {
        Group {
            HStack {
                sectionTitle("Recorded tokens")
                Spacer()
                Picker("Period", selection: $days) { Text("Today").tag(1); Text("7 days").tag(7); Text("30 days").tag(30) }
                    .pickerStyle(.menu).labelsHidden().fixedSize()
            }
            if activity.enabled.contains(provider) {
                if let report {
                    localReport(report)
                    if report.isPartial {
                        DisclosureGroup("Some local records are missing") {
                            note("\(report.skippedCount) skipped; \(report.unattributedCount) unattributed. Missing or inherited activity is not estimated.")
                        }.font(.system(size: 11)).foregroundStyle(.orange)
                    }
                    Text("Read \(report.scannedAt.formatted(date: .omitted, time: .shortened))")
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                } else { ProgressView("Reading local activity…").controlSize(.small) }
                DisclosureGroup("About local activity") {
                    VStack(alignment: .leading, spacing: 10) {
                        note("Includes local records across accounts on this Mac. Other devices and unrecorded web activity are not included. Reasoning is part of output. Token counts do not measure subscription quota.")
                        Button("Turn off local activity") { activity.setEnabled(provider, false) }
                    }.padding(.top, 8)
                }.font(.system(size: 11))
            } else { localConnection }
        }
    }
    private var localConnection: some View {
        VStack(alignment: .leading, spacing: 9) {
            note("Read local \(provider.name) activity to show tokens by model. Glance keeps token metadata in memory and does not save prompts.")
            Button("Enable local activity") { activity.setEnabled(provider, true) }.font(.system(size: 11))
        }
    }
    private func localReport(_ report: LocalActivityReport) -> some View {
        let models = report.aggregates(by: .model, since: since)
        let total = models.reduce(0) { $0 + $1.excludingCache }
        let cached = models.reduce(0) { $0 + $1.cached }
        let processed = models.reduce(0) { $0 + $1.total }
        let byDay = report.aggregates(by: .day, since: since).sorted { $0.id < $1.id }
        let group: LocalActivityReport.Grouping = grouping == "Session" ? .session : grouping == "Project" ? .project : .model
        return VStack(alignment: .leading, spacing: 12) {
            Text(SubscriptionPresentation.tokens(total) + " tokens")
                .font(.system(size: 28, weight: .semibold)).monospacedDigit().help(total.formatted() + " tokens")
            note("On this Mac · Excluding cached input")
            DisclosureGroup("Token breakdown") {
                VStack(alignment: .leading, spacing: 8) {
                    tokenDetail("Excluding cached input", total)
                    tokenDetail("Cached input reused", cached)
                    tokenDetail("Total processed", processed)
                    note("Cached context can be reused on many requests. Total processed includes those repeated reads.")
                }.padding(.top, 8)
            }.font(.system(size: 12))
            if byDay.count == 1, let day = byDay.first {
                HStack {
                    Text(activityDate(day.id))
                    Spacer()
                    Text(SubscriptionPresentation.tokens(day.excludingCache) + " tokens").monospacedDigit()
                }.font(.system(size: 12)).padding(12)
                    .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 8))
            } else if !byDay.isEmpty {
                Chart(byDay) { day in
                    BarMark(x: .value("Day", activityDate(day.id)), y: .value("Tokens excluding cache", day.excludingCache))
                        .foregroundStyle(tint)
                        .annotation(position: .top) {
                            if byDay.count <= 7 {
                                Text(SubscriptionPresentation.tokens(day.excludingCache)).font(.system(size: 11)).foregroundStyle(.secondary)
                            }
                        }
                }
                .chartXAxis { AxisMarks(values: .automatic(desiredCount: 4)) { _ in AxisValueLabel() } }
                .chartYAxis { AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) { value in
                    AxisGridLine()
                    AxisValueLabel { if let count = value.as(Int.self) { Text(SubscriptionPresentation.tokens(count)) } }
                } }
                .chartYScale(domain: 0...max(1, Double(byDay.map(\.excludingCache).max() ?? 0) * 1.25))
                .frame(height: 105)
                .accessibilityLabel("Daily tokens excluding cached input; only days with local records are shown")
            }
            if provider == .codex {
                Picker("Group activity", selection: $grouping) {
                    Text("Model").tag("Model"); Text("Session").tag("Session"); Text("Project").tag("Project")
                }.pickerStyle(.segmented).labelsHidden()
            }
            if models.isEmpty { note("No recorded tokens in this period.") }
            ForEach(Array(activityRows(report, by: group, since: since).prefix(20))) { item in tokenRow(item) }
        }
    }
    private func activityRows(_ report: LocalActivityReport, by grouping: LocalActivityReport.Grouping, since: Date) -> [LocalActivityAggregate] {
        report.aggregates(by: grouping, since: since).sorted {
            $0.excludingCache == $1.excludingCache ? $0.id < $1.id : $0.excludingCache > $1.excludingCache
        }
    }
    private func activityDate(_ value: String) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: value)?.formatted(.dateTime.month(.abbreviated).day()) ?? value
    }
    private func tokenDetail(_ title: String, _ count: Int) -> some View {
        HStack {
            Text(title).foregroundStyle(.secondary)
            Spacer()
            Text(count.formatted()).monospacedDigit().textSelection(.enabled)
        }.font(.system(size: 11))
    }
    private func tokenRow(_ item: LocalActivityAggregate) -> some View {
        VStack(spacing: 8) {
            DisclosureGroup {
                VStack(spacing: 8) {
                    tokenDetail("Uncached input", item.uncachedInput)
                    tokenDetail("Output", item.output)
                    tokenDetail("Cached input reused", item.cached)
                }.padding(.top, 8)
            } label: {
                HStack(alignment: .firstTextBaseline) {
                    Text(item.id).lineLimit(2).truncationMode(.middle).help(item.id)
                    Spacer(minLength: 8)
                    Text(SubscriptionPresentation.tokens(item.excludingCache)).monospacedDigit().fontWeight(.medium)
                        .help(item.excludingCache.formatted() + " tokens excluding cached input")
                }
            }.font(.system(size: 12))
            Divider()
        }
    }
    private var historyContent: some View {
        Group {
            sectionTitle("Quota history · On this Mac")
            if !history.enabled {
                note("Save allowance observations for 90 days. History starts when enabled; previous usage cannot be recovered.")
                Button("Enable history") { enableHistory() }
            } else {
                if let windows = usage?.windows, !windows.isEmpty {
                    Picker("Allowance", selection: $selectedWindow) {
                        Text(weekly?.title ?? "Choose allowance").tag("")
                        ForEach(windows.filter { $0.id != weekly?.id }) { Text($0.title).tag($0.id) }
                    }.font(.system(size: 11))
                }
                if periods.isEmpty { historyEmpty }
                else {
                    Picker("Period", selection: $selectedPeriod) {
                        Text("Latest observed period").tag(nil as UUID?)
                        ForEach(periods) { period in
                            Text("Reset \(period.reset.formatted(date: .abbreviated, time: .shortened))").tag(Optional(period.id))
                        }
                    }.font(.system(size: 11))
                    if let period = periods.first(where: { $0.id == selectedPeriod }) ?? periods.first {
                        Text("\(100 - period.last.used, specifier: "%.1f")% remaining").font(.system(size: 24, weight: .semibold))
                        note("Last observed \(period.last.date.formatted(date: .abbreviated, time: .shortened))")
                        sectionTitle("Observed consumption")
                        QuotaDayChart(days: period.days(), tint: tint)
                        ForEach(period.days().count > 1 ? period.days() : []) { day in
                            HStack {
                                Text(day.date.formatted(date: .abbreviated, time: .omitted)); Spacer()
                                Text(day.value.map { String(format: "+%.1f pp · partial", $0) } ?? "No coverage")
                            }.font(.system(size: 11))
                        }
                    }
                }
                note("pp = percentage points. Partial observations; gaps are unknown, not zero usage.")
                DisclosureGroup("How history is measured") {
                    note("Only observed increases are counted, in percentage points. First readings, resets, long gaps and midnight crossings do not establish exact daily totals. History stays separate for each account and plan.")
                        .padding(.top, 8)
                }.font(.system(size: 11))
                if let error = history.error { note(error, warning: true) }
                DisclosureGroup("Manage history") {
                    VStack(alignment: .leading, spacing: 10) {
                        note("Kept for 90 days. These actions delete saved history for both providers.")
                        HStack {
                            Button("Clear history") { history.clear() }
                            Spacer()
                            Button("Disable & delete") { history.setEnabled(false) }
                        }
                    }.padding(.top, 8)
                }.font(.system(size: 11))
            }
        }
    }
    private var historyEmpty: some View {
        Text(usage?.accountID == nil ? "History needs a verified account identity. Refresh after signing in." : "Collecting observations. Daily changes appear after two readings in the same period.")
            .font(.system(size: 11)).foregroundStyle(.secondary)
    }
    private func enableHistory() {
        history.setEnabled(true)
        for (provider, state) in store.states { if let usage = state.usage { history.record(provider, usage) } }
    }
    private func sectionTitle(_ title: String) -> some View { Text(title).font(.system(size: 12, weight: .semibold)) }
    private func note(_ text: String, warning: Bool = false) -> some View {
        Text(text).font(.system(size: 11)).foregroundStyle(warning ? Color.orange : Color.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}

private struct QuotaDayChart: View {
    let days: [QuotaDay]
    let tint: Color
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if days.count == 1, let day = days.first {
                HStack {
                    Text(day.date.formatted(.dateTime.month(.abbreviated).day()))
                    Spacer()
                    Text(day.value.map { String(format: "+%.1f pp", $0) } ?? "No coverage")
                        .monospacedDigit().fontWeight(.medium)
                }.font(.system(size: 12)).padding(12)
                    .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 8))
            } else {
                Chart(days) { day in
                    if let value = day.value {
                        BarMark(x: .value("Day", day.date, unit: .day), y: .value("Observed percentage points", value))
                            .foregroundStyle(tint)
                            .annotation(position: .top) {
                                if days.count <= 7 { Text(value, format: .number.precision(.fractionLength(1))).font(.system(size: 11)).foregroundStyle(.secondary) }
                            }
                    } else {
                        PointMark(x: .value("Day", day.date, unit: .day), y: .value("Unknown", 0)).symbol(.cross).foregroundStyle(.secondary)
                    }
                }
                .chartXAxis { AxisMarks(values: .stride(by: .day, count: max(1, days.count / 4))) { _ in AxisValueLabel(format: .dateTime.month(.abbreviated).day()) } }
                .chartYAxis { AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) }
                .chartYScale(domain: 0...max(1, (days.compactMap(\.value).max() ?? 0) * 1.25))
                .frame(height: 110).accessibilityLabel("Observed daily quota changes. Crosses indicate missing coverage.")
                Text("Percentage points · × no coverage").font(.system(size: 11)).foregroundStyle(.secondary)
            }
        }
    }
}

private struct FullRowDisclosureStyle: DisclosureGroupStyle {
    func makeBody(configuration: Configuration) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Button { configuration.isExpanded.toggle() } label: {
                HStack(spacing: 4) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(configuration.isExpanded ? 90 : 0))
                        .frame(width: 10)
                        .accessibilityHidden(true)
                    configuration.label.frame(maxWidth: .infinity, alignment: .leading)
                }.contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityValue(configuration.isExpanded ? "Expanded" : "Collapsed")
            if configuration.isExpanded {
                configuration.content.padding(.leading, 14)
            }
        }
    }
}
