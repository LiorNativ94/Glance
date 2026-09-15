import Foundation
import GlanceCore

final class QuotaHistoryStore: ObservableObject {
    @Published private(set) var history = QuotaHistory()
    @Published private(set) var enabled: Bool
    @Published private(set) var error: String?
    private var loaded = false
    private var generation = UUID()
    private var pending: [(SubscriptionProvider, SubscriptionUsage)] = []
    private let defaults: UserDefaults
    private let file: URL
    private let queue = DispatchQueue(label: "Glance.quota-history", qos: .utility)

    init(defaults: UserDefaults = .standard, directory: URL? = nil) {
        self.defaults = defaults
        enabled = defaults.bool(forKey: "quotaHistoryEnabled")
        let root = directory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Glance")
        file = root.appendingPathComponent("quota-history.json")
        loaded = !enabled
        if enabled {
            let file = file, id = generation
            queue.async { [weak self] in
                var saved = (try? Data(contentsOf: file)).flatMap { try? JSONDecoder().decode(QuotaHistory.self, from: $0) } ?? QuotaHistory()
                saved.prune()
                DispatchQueue.main.async {
                    guard let self, self.generation == id, self.enabled else { return }
                    self.history = saved; self.loaded = true
                    let pending = self.pending; self.pending.removeAll()
                    for (provider, usage) in pending { self.record(provider, usage) }
                }
            }
        }
    }
    func setEnabled(_ value: Bool) {
        enabled = value
        defaults.set(value, forKey: "quotaHistoryEnabled")
        if !value { clear() }
    }
    func clear() {
        generation = UUID(); loaded = true; pending.removeAll(); error = nil
        history = QuotaHistory()
        let file = file
        // Wait for older atomic writes before deleting; a queued write must never resurrect cleared history.
        queue.sync { try? FileManager.default.removeItem(at: file) }
    }
    func record(_ provider: SubscriptionProvider, _ usage: SubscriptionUsage) {
        guard enabled else { return }
        guard loaded else { pending.append((provider, usage)); return }
        history.record(provider: provider, usage: usage)
        let snapshot = history, file = file, id = generation
        queue.async { [weak self] in
            do {
                try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true,
                                                       attributes: [.posixPermissions: 0o700])
                try JSONEncoder().encode(snapshot).write(to: file, options: .atomic)
                try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
                DispatchQueue.main.async { if self?.generation == id { self?.error = nil } }
            } catch { DispatchQueue.main.async { if self?.generation == id { self?.error = "History could not be saved on this Mac." } } }
        }
    }
}
