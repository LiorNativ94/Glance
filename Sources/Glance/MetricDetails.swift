import SwiftUI
import GlanceCore

struct MetricDetails: View {
    @ObservedObject var model: AppModel
    let id: String
    @AccessibilityFocusState private var homeFocused: Bool
    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 8) {
                Button { model.goHome() } label: { Label("Back to Glance", systemImage: "chevron.left") }
                    .buttonStyle(.plain).font(.system(size: 11)).foregroundStyle(.blue)
                    .accessibilityIdentifier("back-to-glance").accessibilityFocused($homeFocused)
                Spacer(minLength: 0)
                MetricIcon(name: model.icon(for: id)).frame(width: 17, height: 17)
                Text(id == "cpu" ? "CPU" : id.capitalized).font(.system(size: 15, weight: .semibold))
            }
            Divider()
            if let provider = SubscriptionProvider(rawValue: id) {
                SubscriptionDetails(model: model, store: model.subscriptions, history: model.quotaHistory,
                                    activity: model.localActivity, sessions: model.sessions(for: provider), provider: provider)
                    .id(provider)
            } else {
                ProcessDetails(model: model, store: model.processes, memory: id == "memory")
                    .id(id)
            }
        }.frame(height: model.detailHeight, alignment: .top)
            .onAppear { homeFocused = true }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("detail-" + id)
    }
}

struct ProcessDetails: View {
    @ObservedObject var model: AppModel
    @ObservedObject var store: ProcessStore
    let memory: Bool
    @State private var expanded = false
    private var rows: [ProcessReading] {
        store.snapshot.processes.filter { memory || $0.cpuPercent != nil }.sorted {
            let a = memory ? Double($0.residentBytes) : ($0.cpuPercent ?? -1)
            let b = memory ? Double($1.residentBytes) : ($1.cpuPercent ?? -1)
            return a == b ? $0.pid < $1.pid : a > b
        }
    }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 15) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(memory ? ReadingFormat.memory(model.snapshot.memoryUsed, total: model.snapshot.memoryTotal) : ReadingFormat.percent(model.snapshot.cpu))
                            .font(.system(size: memory ? 22 : 30, weight: .semibold)).monospacedDigit()
                        Text(memory ? "Memory used" : "Total CPU usage").font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Sparkline(values: memory ? model.memoryHistory : model.cpuHistory).frame(width: 110, height: 40)
                }
                Text("Recent 60 seconds").font(.system(size: 10)).foregroundStyle(.secondary)
                if memory {
                    Label("Memory pressure: \(store.snapshot.pressure.rawValue)", systemImage: "circle.fill")
                        .font(.system(size: 11)).foregroundStyle(pressureColor)
                        .padding(10).frame(maxWidth: .infinity, alignment: .leading)
                        .background(pressureColor.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
                    HStack {
                        detail("Swap", store.snapshot.swapBytes)
                        Spacer()
                        detail("Compressed", store.snapshot.compressedBytes)
                    }
                }
                Divider()
                HStack {
                    Text("Top processes").font(.system(size: 13, weight: .semibold))
                    Spacer()
                    Text(memory ? "Resident memory ↓" : "CPU ↓").font(.system(size: 10)).foregroundStyle(.secondary)
                }
                if rows.isEmpty { Text(memory ? "Reading processes…" : "Measuring CPU activity…").font(.system(size: 12)).foregroundStyle(.secondary) }
                VStack(spacing: 0) {
                    ForEach(Array(rows.prefix(expanded ? 10 : 5))) { row in
                        HStack(spacing: 8) {
                            ProcessIcon(pid: row.pid).frame(width: 20, height: 20)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(row.name).lineLimit(1).truncationMode(.middle)
                                Text("PID \(row.pid)").font(.system(size: 9)).foregroundStyle(.tertiary)
                            }.frame(maxWidth: .infinity, alignment: .leading)
                            Text(memory ? bytes(row.residentBytes) : cpu(row.cpuPercent)).monospacedDigit().lineLimit(1)
                                .frame(width: 66, alignment: .trailing)
                            Text(memory ? cpu(row.cpuPercent) : bytes(row.residentBytes)).monospacedDigit().lineLimit(1)
                                .foregroundStyle(.secondary).frame(width: 57, alignment: .trailing)
                        }.font(.system(size: 11)).padding(.vertical, 9)
                            .accessibilityElement(children: .combine)
                        Divider()
                    }
                }
                Text(memory ? "Resident memory is RAM held by each process; shared pages can appear in several rows." : "Process CPU: 100% = one logical core. Total CPU is measured across all cores.")
                    .font(.system(size: 10)).foregroundStyle(.secondary)
                Text("Updates every 2 seconds while open.").font(.system(size: 10)).foregroundStyle(.secondary)
            }.padding(.bottom, 4)
        }
        HStack {
            Button(expanded ? "Show 5" : "Show 10") { expanded.toggle() }
                .accessibilityIdentifier("process-count")
            Spacer()
            Button("Activity Monitor ↗") {
                NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Utilities/Activity Monitor.app"))
            }
        }.buttonStyle(.plain).font(.system(size: 11)).foregroundStyle(.blue)
    }
    private var pressureColor: Color {
        switch store.snapshot.pressure { case .normal: return .green; case .warning: return .orange; case .critical: return .red; case .unknown: return .secondary }
    }
    private func cpu(_ value: Double?) -> String { value.map { String(format: "%.1f%%", $0) } ?? "—" }
    private func bytes(_ value: UInt64) -> String { ByteCountFormatter.string(fromByteCount: Int64(clamping: value), countStyle: .memory) }
    private func detail(_ title: String, _ value: UInt64?) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).foregroundStyle(.secondary)
            Text(value.map(bytes) ?? "Unavailable").monospacedDigit()
        }.font(.system(size: 11))
    }
}

private struct ProcessIcon: View {
    let pid: Int32
    var body: some View {
        if let icon = NSRunningApplication(processIdentifier: pid)?.icon {
            Image(nsImage: icon).resizable().scaledToFit()
        } else { Image(systemName: "terminal").foregroundStyle(.secondary) }
    }
}
