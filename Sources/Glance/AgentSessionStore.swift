import Foundation
import GlanceCore

enum AgentSessionEvent: Equatable {
    case ready(AgentSession)
    case needsInput(AgentSession)
    case needsApproval(AgentSession)
    case failed(AgentSession)
}

final class AgentSessionStore: ObservableObject {
    static let sharedCodex = AgentSessionStore.codex()
    static let sharedClaude = AgentSessionStore.claude()
    @Published private(set) var snapshot = AgentSessionSnapshot()
    var onEvent: ((AgentSessionEvent) -> Void)?

    let provider: SubscriptionProvider
    private let read: () -> AgentSessionSnapshot
    private let reportsUnseenCompletions: Bool
    private let queue: DispatchQueue
    private var timer: Timer?
    private var reading = false
    private var baselineLoaded = false

    /// `reportsUnseenCompletions` treats a finished session that appeared between scans as a completion.
    init(provider: SubscriptionProvider, interval: TimeInterval, reportsUnseenCompletions: Bool,
         startsTimer: Bool, read: @escaping () -> AgentSessionSnapshot) {
        self.provider = provider; self.read = read; self.reportsUnseenCompletions = reportsUnseenCompletions
        queue = DispatchQueue(label: "Glance.\(provider.rawValue)-sessions", qos: .utility)
        refresh()
        if startsTimer {
            timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in self?.refresh() }
            timer?.tolerance = interval / 5
        }
    }

    static func codex(root: URL = CodexSessionReader.defaultRoot(),
                      catalogURL: URL? = CodexSessionReader.defaultCatalogURL(),
                      reader: CodexSessionReader = CodexSessionReader(),
                      startsTimer: Bool = true) -> AgentSessionStore {
        AgentSessionStore(provider: .codex, interval: 5, reportsUnseenCompletions: true, startsTimer: startsTimer) {
            reader.read(root: root, catalogURL: catalogURL)
        }
    }

    /// Claude's registry is a handful of small files, so it is polled often enough to catch short turns.
    static func claude(root: URL = ClaudeSessionReader.defaultRoot(),
                       reader: ClaudeSessionReader = ClaudeSessionReader(),
                       startsTimer: Bool = true) -> AgentSessionStore {
        AgentSessionStore(provider: .claude, interval: 2, reportsUnseenCompletions: false, startsTimer: startsTimer) {
            reader.read(root: root)
        }
    }

    deinit { timer?.invalidate() }

    var sessions: [AgentSession] { snapshot.sessions }
    var activeCount: Int { snapshot.activeCount }
    var attentionCount: Int { snapshot.attentionCount }

    func refresh() {
        guard !reading else { return }
        reading = true
        queue.async { [weak self] in
            guard let self else { return }
            let next = self.read()
            DispatchQueue.main.async {
                let previous = self.snapshot
                self.snapshot = next
                if self.baselineLoaded { self.emitTransitions(from: previous, to: next) }
                self.baselineLoaded = true
                self.reading = false
            }
        }
    }

    private func emitTransitions(from previous: AgentSessionSnapshot, to next: AgentSessionSnapshot) {
        let old = Dictionary(uniqueKeysWithValues: previous.sessions.map { ($0.id, $0) })
        for session in next.sessions {
            let prior = old[session.id]
            guard prior?.status != session.status else { continue }
            switch session.status {
            case .needsInput: onEvent?(.needsInput(session))
            case .needsApproval: onEvent?(.needsApproval(session))
            case .failed where prior?.status.isActive == true: onEvent?(.failed(session))
            case .ready where prior?.status.isActive == true
                || (reportsUnseenCompletions && prior == nil && session.updatedAt > previous.scannedAt): onEvent?(.ready(session))
            default: break
            }
        }
    }
}
