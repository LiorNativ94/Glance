import SwiftUI
import GlanceCore

struct SubscriptionCards: View {
    @ObservedObject var store: SubscriptionStore
    var body: some View {
        VStack(spacing: 12) {
            ForEach(SubscriptionProvider.allCases) { provider in
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        MetricIcon(name: "\(provider.rawValue)-usage").frame(width: 18, height: 18)
                        Text(provider.name).font(.system(size: 13, weight: .semibold))
                        Spacer()
                        Toggle("Connect \(provider.name)", isOn: Binding(
                            get: { store.enabled.contains(provider) }, set: { store.setEnabled(provider, $0) }))
                            .labelsHidden().toggleStyle(.switch).controlSize(.small)
                            .accessibilityIdentifier("connect-\(provider.rawValue)")
                    }
                    if store.enabled.contains(provider) {
                        let state = store.states[provider] ?? SubscriptionStore.State()
                        if let usage = state.usage {
                            if let plan = usage.plan {
                                Text(plan.replacingOccurrences(of: "_", with: " ").capitalized)
                                    .font(.system(size: 10, weight: .medium)).foregroundStyle(.secondary)
                            }
                            if usage.windows.isEmpty {
                                Text("This account doesn’t report numeric usage limits.").font(.system(size: 11))
                            }
                            TimelineView(.periodic(from: .now, by: 60)) { context in
                                VStack(alignment: .leading, spacing: 10) {
                                    ForEach(usage.windows) { window in
                                        VStack(alignment: .leading, spacing: 4) {
                                            HStack {
                                                Text(window.title)
                                                Spacer()
                                                Text("\(Int(window.usedPercent.rounded()))% used").monospacedDigit()
                                            }.font(.system(size: 11))
                                            ProgressView(value: window.usedPercent, total: 100)
                                                .tint(window.usedPercent >= 90 ? .orange : .blue)
                                            Text(window.resetDescription(now: context.date))
                                                .font(.system(size: 10)).foregroundStyle(.secondary)
                                        }
                                    }
                                    Text(context.date.timeIntervalSince(usage.updatedAt) >= 600 ? "Reading is out of date" : "Updated \(usage.updatedAt.formatted(date: .omitted, time: .shortened))")
                                        .font(.system(size: 10)).foregroundStyle(.secondary)
                                }
                            }
                        }
                        if let error = state.error {
                            Text(error).font(.system(size: 11)).foregroundStyle(.orange)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        HStack {
                            Button(state.refreshing ? "Refreshing…" : "Refresh") {
                                store.refresh(provider, allowInteraction: true)
                            }.disabled(state.refreshing).accessibilityIdentifier("refresh-\(provider.rawValue)")
                            Spacer()
                            Link("Usage page ↗", destination: provider.usageURL)
                        }.font(.system(size: 10))
                    } else {
                        Text(provider.signInHelp).font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                    Text(provider == .claude
                         ? "Uses your Claude Code sign-in. macOS may ask for Keychain access."
                         : "Uses your Codex CLI sign-in. API keys don’t include subscription limits.")
                        .font(.system(size: 10)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }.padding(12).frame(maxWidth: .infinity, alignment: .leading)
                    .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 12))
            }
        }
    }
}
