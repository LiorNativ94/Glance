import AppKit
import Combine
import GlanceCore
import ServiceManagement

final class AppModel: ObservableObject {
    @Published var snapshot = SystemSnapshot()
    @Published var cpuHistory: [Double] = []
    @Published var memoryHistory: [Double] = []
    @Published var page: Page = .overview { didSet { updateDetailActivity(); onRouteChange?() } }
    @Published var detailHeight: CGFloat = 560
    var panelVisible = false { didSet { updateDetailActivity() } }
    let processes = ProcessStore()
    let quotaHistory: QuotaHistoryStore
    let localActivity: LocalActivityStore
    let codexSessions: AgentSessionStore
    let claudeSessions: AgentSessionStore
    func sessions(for provider: SubscriptionProvider) -> AgentSessionStore { provider == .claude ? claudeSessions : codexSessions }
    var providerTabs: [SubscriptionProvider: String] = [:]
    var onRouteChange: (() -> Void)?
    var detailMetric: String? { if case .metric(let id) = page { return id }; return nil }
    var panelWidth: CGFloat { detailMetric == nil ? 320 : 360 }
    func openMetric(_ id: String) {
        page = ["cpu", "memory", "claude", "codex"].contains(id) ? .metric(id) : .overview
    }
    func goHome() { page = .overview }
    private func updateDetailActivity() {
        processes.setActive(panelVisible && ["cpu", "memory"].contains(detailMetric ?? ""))
        let provider = detailMetric.flatMap(SubscriptionProvider.init(rawValue:))
        localActivity.setActive(panelVisible && provider.map(subscriptions.enabled.contains) == true ? provider : nil)
    }
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
    @Published var claudeMenuLimit: MenuLimit {
        didSet { defaults.set(claudeMenuLimit.rawValue, forKey: "claudeMenuLimit"); onMenuChange?() }
    }
    /// Which Claude allowance the menu bar and notch show.
    enum MenuLimit: String, CaseIterable {
        case lowest, fiveHour = "five_hour", weekly = "seven_day"
        var title: String {
            switch self {
            case .lowest: "Lowest"
            case .fiveHour: "5-hour"
            case .weekly: "Weekly"
            }
        }
        var windowID: String? { self == .lowest ? nil : rawValue }
    }
    enum Appearance: String, CaseIterable {
        case system, light, dark
        var title: String { rawValue.capitalized }
        var native: NSAppearance? {
            switch self {
            case .system: nil
            case .light: NSAppearance(named: .aqua)
            case .dark: NSAppearance(named: .darkAqua)
            }
        }
    }
    @Published var appearance: Appearance {
        didSet { defaults.set(appearance.rawValue, forKey: "dashboardAppearance"); onAppearanceChange?() }
    }
    var onAppearanceChange: (() -> Void)?
    @Published var settingsError: String?
    @Published var sectionOrder: [DashboardSection] {
        didSet { defaults.set(sectionOrder.map(\.rawValue), forKey: "dashboardSectionOrder") }
    }
    @Published var hiddenSections: Set<DashboardSection> {
        didSet { defaults.set(hiddenSections.map(\.rawValue), forKey: "hiddenDashboardSections") }
    }
    @Published private(set) var enabledAlerts: Set<AlertKind> {
        didSet {
            defaults.set(enabledAlerts.map(\.rawValue), forKey: "enabledAlerts")
            updatePressureMonitoring()
            evaluateAlerts()
        }
    }
    @Published private(set) var pendingAlerts: Set<AlertKind> = []
    @Published private(set) var alertThresholds: AlertThresholds {
        didSet {
            defaults.set(alertThresholds.aiRemainingPercent, forKey: "alertAIRemainingPercent")
            defaults.set(alertThresholds.storageFreePercent, forKey: "alertStorageFreePercent")
            defaults.set(alertThresholds.storageFreeGB, forKey: "alertStorageFreeGB")
            evaluateAlerts()
        }
    }
    @Published private(set) var memoryPressure = false
    var alertToReview: GlanceAlert?
    var authorizeAlerts: ((@escaping (Bool, String?) -> Void) -> Void)?
    var onAlert: ((GlanceAlert) -> Void)?
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
    private var sessionChanges: [AnyCancellable] = []
    private var pressureSource: DispatchSourceMemoryPressure?
    private var alertPolicy = AlertPolicy()
    enum Page: Equatable { case overview, customize, settings, lidSetup, subscriptions, dashboardLayout, alerts, alertDetail, metric(String) }

    init(defaults: UserDefaults = .standard, subscriptions: SubscriptionStore? = nil,
         quotaHistory: QuotaHistoryStore? = nil, localActivity: LocalActivityStore? = nil,
         codexSessions: AgentSessionStore? = nil, claudeSessions: AgentSessionStore? = nil) {
        self.defaults = defaults
        self.quotaHistory = quotaHistory ?? QuotaHistoryStore(defaults: defaults)
        self.localActivity = localActivity ?? LocalActivityStore(defaults: defaults)
        self.codexSessions = codexSessions ?? .sharedCodex
        self.claudeSessions = claudeSessions ?? .sharedClaude
        self.subscriptions = subscriptions ?? SubscriptionStore(defaults: defaults)
        alertThresholds = AlertThresholds(aiRemainingPercent: defaults.object(forKey: "alertAIRemainingPercent") as? Int ?? 20,
                                          storageFreePercent: defaults.object(forKey: "alertStorageFreePercent") as? Int ?? 5,
                                          storageFreeGB: defaults.object(forKey: "alertStorageFreeGB") as? Int ?? 10)
        sectionOrder = DashboardSection.restored(defaults.stringArray(forKey: "dashboardSectionOrder"))
        hiddenSections = Set((defaults.stringArray(forKey: "hiddenDashboardSections") ?? []).compactMap(DashboardSection.init(rawValue:)))
        enabledAlerts = Set((defaults.stringArray(forKey: "enabledAlerts") ?? []).compactMap(AlertKind.init(rawValue:)))
        showInNotch = defaults.bool(forKey: "showInNotch")
        claudeMenuLimit = MenuLimit(rawValue: defaults.string(forKey: "claudeMenuLimit") ?? "") ?? .lowest
        appearance = Appearance(rawValue: defaults.string(forKey: "dashboardAppearance") ?? "") ?? .system
        selected = defaults.stringArray(forKey: "selectedMetrics") ?? MetricSelection.defaults
        showAwakeIcon = defaults.bool(forKey: "showAwakeIcon")
        launchAtLogin = SMAppService.mainApp.status == .enabled
        self.subscriptions.onUsage = { [weak self] provider, usage in
            self?.quotaHistory.record(provider, usage)
        }
        powerChanges = power.objectWillChange.sink { [weak self] in
            DispatchQueue.main.async { self?.onMenuChange?() }
        }
        subscriptionChanges = self.subscriptions.objectWillChange.sink { [weak self] in
            DispatchQueue.main.async {
                self?.objectWillChange.send()
                self?.onMenuChange?()
                self?.evaluateAlerts()
                self?.updateDetailActivity()
            }
        }
        for store in [self.codexSessions, self.claudeSessions] {
            store.onEvent = { [weak self, provider = store.provider] event in self?.handleSession(event, provider: provider) }
            sessionChanges.append(store.objectWillChange.sink { [weak self] in
                DispatchQueue.main.async {
                    self?.objectWillChange.send()
                    self?.onMenuChange?()
                }
            })
        }
        for name in [NSWorkspace.didMountNotification, NSWorkspace.didUnmountNotification, NSWorkspace.didWakeNotification] {
            observers.append(NSWorkspace.shared.notificationCenter.addObserver(forName: name, object: nil, queue: .main) {
                [weak self] _ in
                self?.sample(refreshStorage: true)
                if name == NSWorkspace.didWakeNotification { self?.subscriptions.refreshAll() }
            })
        }
        sample(refreshStorage: true)
        updatePressureMonitoring()
        samplingTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in self?.sample() }
        samplingTimer?.tolerance = 0.3
    }
    deinit {
        samplingTimer?.invalidate()
        pressureSource?.cancel()
        observers.forEach { NSWorkspace.shared.notificationCenter.removeObserver($0) }
    }

    var visibleSections: [DashboardSection] {
        sectionOrder.filter { section in
            if section == .awake && power.active { return true }
            return !hiddenSections.contains(section)
        }
    }
    func moveSection(_ section: DashboardSection, by offset: Int) {
        guard let index = sectionOrder.firstIndex(of: section), sectionOrder.indices.contains(index + offset) else { return }
        sectionOrder.swapAt(index, index + offset)
    }
    func setAlertEnabled(_ kind: AlertKind, _ enabled: Bool) {
        guard !pendingAlerts.contains(kind) else { return }
        if !enabled { enabledAlerts.remove(kind); return }
        guard let authorizeAlerts else { return }
        pendingAlerts.insert(kind)
        authorizeAlerts { [weak self] allowed, error in
            DispatchQueue.main.async {
                guard let self else { return }
                self.pendingAlerts.remove(kind)
                if allowed { self.enabledAlerts.insert(kind) }
                else { self.settingsError = error ?? "Allow Glance notifications in System Settings → Notifications, then try again." }
            }
        }
    }
    func retryAlert(_ alert: GlanceAlert) { alertPolicy.retry(alert) }
    func updateAlertThresholds(ai: Int? = nil, storagePercent: Int? = nil, storageGB: Int? = nil) {
        alertThresholds = AlertThresholds(aiRemainingPercent: ai ?? alertThresholds.aiRemainingPercent,
                                          storageFreePercent: storagePercent ?? alertThresholds.storageFreePercent,
                                          storageFreeGB: storageGB ?? alertThresholds.storageFreeGB)
    }
    private func evaluateAlerts() {
        guard let onAlert else { return }
        let usages = subscriptions.states.compactMapValues(\.usage)
        for alert in alertPolicy.evaluate(enabled: enabledAlerts, snapshot: snapshot,
                                           memoryPressure: memoryPressure, usages: usages, thresholds: alertThresholds) { onAlert(alert) }
    }
    private func handleSession(_ event: AgentSessionEvent, provider: SubscriptionProvider) {
        let kind: AlertKind = provider == .claude ? .claudeSessions : .codexSessions
        guard enabledAlerts.contains(kind), let onAlert else { return }
        let session: AgentSession
        let title: String
        switch event {
        case .ready(let value): session = value; title = "\(provider.name) agent finished"
        case .needsInput(let value): session = value; title = "\(provider.name) needs your input"
        case .needsApproval(let value): session = value; title = "\(provider.name) needs approval"
        case .failed(let value): session = value; title = "\(provider.name) agent stopped with an error"
        }
        let destination = session.deepLink?.absoluteString
        onAlert(GlanceAlert(id: "\(provider.rawValue)-session:\(session.id):\(session.status.rawValue):\(session.updatedAt.timeIntervalSince1970)",
                            kind: kind, title: title,
                            body: "\(session.title) · \(session.project)", destination: destination))
    }
    private func updatePressureMonitoring() {
        guard enabledAlerts.contains(.memory) else {
            pressureSource?.cancel(); pressureSource = nil; memoryPressure = false
            return
        }
        guard pressureSource == nil else { return }
        let source = DispatchSource.makeMemoryPressureSource(eventMask: [.normal, .warning, .critical], queue: .main)
        source.setEventHandler { [weak self, weak source] in
            guard let self, let source else { return }
            self.memoryPressure = !source.data.intersection([.warning, .critical]).isEmpty
            self.evaluateAlerts()
        }
        pressureSource = source
        source.resume()
    }

    var metricChoices: [(id: String, name: String, icon: String)] {
        var items = [("cpu", "CPU", "cpu"), ("memory", "Memory", "memorychip")]
        items += snapshot.volumes.map { ($0.id, $0.name, $0.isInternal ? "internaldrive" : "externaldrive") }
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
        case "claude": return ReadingFormat.percent(subscriptions.states[.claude]?.usage?.window(claudeMenuLimit.windowID)?.remainingFraction)
        case "codex": return ReadingFormat.percent(subscriptions.remaining(.codex))
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
                self.evaluateAlerts()
                self.reading = false
                self.onMenuChange?()
            }
        }
    }
}
