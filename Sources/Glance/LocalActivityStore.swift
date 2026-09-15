import Foundation
import GlanceCore

final class LocalActivityStore: ObservableObject {
    @Published private(set) var enabled: Set<SubscriptionProvider>
    @Published private(set) var reports: [SubscriptionProvider: LocalActivityReport] = [:]
    @Published private(set) var refreshing: Set<SubscriptionProvider> = []
    private let roots: (SubscriptionProvider) -> [URL]
    private let defaults: UserDefaults
    private let queue = DispatchQueue(label: "Glance.local-activity", qos: .utility)
    private var reader = LocalActivityReader()
    private var generation: [SubscriptionProvider: UUID] = [:]
    private var active: SubscriptionProvider?
    private var timer: Timer?
    init(defaults: UserDefaults = .standard, roots: @escaping (SubscriptionProvider) -> [URL] = { LocalActivityReader.defaultRoots(provider: $0) }) {
        self.defaults = defaults; self.roots = roots
        enabled = Set((defaults.stringArray(forKey: "localActivityProviders") ?? []).compactMap(SubscriptionProvider.init(rawValue:)))
    }
    deinit { timer?.invalidate() }
    func setEnabled(_ provider: SubscriptionProvider, _ value: Bool) {
        if value { enabled.insert(provider) } else {
            enabled.remove(provider); reports.removeValue(forKey: provider)
            generation.removeValue(forKey: provider); refreshing.remove(provider)
            queue.async { self.reader = LocalActivityReader() }
        }
        defaults.set(enabled.map(\.rawValue), forKey: "localActivityProviders")
        if value { refresh(provider) }
    }
    func setActive(_ provider: SubscriptionProvider?) {
        guard active != provider else { return }
        active = provider
        timer?.invalidate(); timer = nil
        guard let provider else { return }
        refresh(provider)
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in self?.refresh(provider) }
        timer?.tolerance = 10
    }
    func refresh(_ provider: SubscriptionProvider) {
        guard enabled.contains(provider), !refreshing.contains(provider) else { return }
        let id = UUID()
        generation[provider] = id; refreshing.insert(provider)
        queue.async { [weak self] in
            guard let self else { return }
            let report = self.reader.read(provider: provider, roots: self.roots(provider),
                                          since: Calendar.current.startOfDay(for: .now).addingTimeInterval(-29 * 86400))
            DispatchQueue.main.async {
                guard self.generation[provider] == id, self.enabled.contains(provider) else { return }
                self.reports[provider] = report; self.refreshing.remove(provider)
            }
        }
    }
}
