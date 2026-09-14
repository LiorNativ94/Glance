import AppKit
import Combine
import GlanceCore
import ServiceManagement

final class AppModel: ObservableObject {
    @Published var snapshot = SystemSnapshot()
    @Published var cpuHistory: [Double] = []
    @Published var memoryHistory: [Double] = []
    @Published var page: Page = .overview
    @Published var selected: [String] {
        didSet { defaults.set(selected, forKey: "selectedMetrics"); onMenuChange?() }
    }
    @Published var showAwakeIcon: Bool {
        didSet { defaults.set(showAwakeIcon, forKey: "showAwakeIcon"); onMenuChange?() }
    }
    @Published var launchAtLogin = false
    @Published var showInNotch: Bool {
        didSet { defaults.set(showInNotch, forKey: "showInNotch"); onNotchChange?() }
    }
    @Published var settingsError: String?
    let power = PowerController()
    let subscriptions: SubscriptionStore
    var onMenuChange: (() -> Void)?
    var onNotchChange: (() -> Void)?
    private let defaults: UserDefaults
    private let reader = SystemReader()
    private let queue = DispatchQueue(label: "Glance.readings", qos: .utility)
    private var samplingTimer: Timer?
    private var reading = false
    private var observers: [NSObjectProtocol] = []
    private var powerChanges: AnyCancellable?
    private var subscriptionChanges: AnyCancellable?
    enum Page { case overview, customize, settings, lidSetup, subscriptions }

    init(defaults: UserDefaults = .standard, subscriptions: SubscriptionStore? = nil) {
        self.defaults = defaults
        self.subscriptions = subscriptions ?? SubscriptionStore(defaults: defaults)
        showInNotch = defaults.bool(forKey: "showInNotch")
        selected = defaults.stringArray(forKey: "selectedMetrics") ?? MetricSelection.defaults
        showAwakeIcon = defaults.bool(forKey: "showAwakeIcon")
        launchAtLogin = SMAppService.mainApp.status == .enabled
        powerChanges = power.objectWillChange.sink { [weak self] in
            DispatchQueue.main.async { self?.onMenuChange?() }
        }
        subscriptionChanges = self.subscriptions.objectWillChange.sink { [weak self] in
            DispatchQueue.main.async {
                self?.objectWillChange.send()
                self?.onMenuChange?()
            }
        }
        for name in [NSWorkspace.didMountNotification, NSWorkspace.didUnmountNotification, NSWorkspace.didWakeNotification] {
            observers.append(NSWorkspace.shared.notificationCenter.addObserver(forName: name, object: nil, queue: .main) {
                [weak self] _ in
                self?.sample(refreshStorage: true)
                if name == NSWorkspace.didWakeNotification { self?.subscriptions.refreshAll() }
            })
        }
        sample(refreshStorage: true)
        samplingTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in self?.sample() }
        samplingTimer?.tolerance = 0.3
    }
    deinit {
        samplingTimer?.invalidate()
        observers.forEach { NSWorkspace.shared.notificationCenter.removeObserver($0) }
    }

    var metricChoices: [(id: String, name: String, icon: String)] {
        var items = [("cpu", "CPU", "cpu"), ("memory", "Memory", "memorychip")]
        items += snapshot.volumes.map { ($0.id, $0.name, $0.isInternal ? "internaldrive" : "externaldrive") }
        if snapshot.battery != nil { items.append(("battery", "Battery", "battery.100")) }
        items += SubscriptionProvider.allCases.filter { subscriptions.enabled.contains($0) }
            .map { ($0.rawValue, "\($0.name) remaining", "\($0.rawValue)-usage") }
        return items
    }
    var visibleMetrics: [String] {
        MetricSelection.visible(selected: selected, available: Set(metricChoices.map(\.id)))
    }
    func icon(for id: String) -> String { metricChoices.first { $0.id == id }?.icon ?? "externaldrive" }
    func name(for id: String) -> String { metricChoices.first { $0.id == id }?.name ?? id }
    func value(for id: String) -> String {
        switch id {
        case "cpu": return ReadingFormat.percent(snapshot.cpu)
        case "memory": return ReadingFormat.percent(snapshot.memoryFraction)
        case "battery": return ReadingFormat.percent(snapshot.battery?.fraction)
        case "claude", "codex": return ReadingFormat.percent(subscriptions.remaining(SubscriptionProvider(rawValue: id)!))
        default: return ReadingFormat.percent(snapshot.volumes.first { $0.id == id }?.fraction)
        }
    }
    func setSelected(_ id: String, enabled: Bool) {
        if enabled, !selected.contains(id) { selected.append(id) }
        else if !enabled { selected.removeAll { $0 == id } }
    }
    func setLogin(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() }
            else { try SMAppService.mainApp.unregister() }
            launchAtLogin = SMAppService.mainApp.status == .enabled
            if enabled && !launchAtLogin { settingsError = "Allow Glance in System Settings → General → Login Items." }
        } catch { settingsError = error.localizedDescription }
    }
    private func sample(refreshStorage: Bool = false) {
        guard !reading else { return }
        reading = true
        queue.async { [weak self] in
            guard let self else { return }
            let sample = reader.read(refreshStorage: refreshStorage)
            DispatchQueue.main.async {
                self.snapshot = sample
                if let cpu = sample.cpu { self.cpuHistory = Array((self.cpuHistory + [cpu]).suffix(30)) }
                if let memory = sample.memoryFraction { self.memoryHistory = Array((self.memoryHistory + [memory]).suffix(30)) }
                self.power.checkBattery(sample.battery)
                self.reading = false
                self.onMenuChange?()
            }
        }
    }
}
