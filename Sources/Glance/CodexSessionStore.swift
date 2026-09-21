import Foundation
import GlanceCore

enum CodexSessionEvent: Equatable {
    case ready(CodexSession)
    case needsInput(CodexSession)
    case needsApproval(CodexSession)
    case failed(CodexSession)
}

final class CodexSessionStore: ObservableObject {
    static let shared = CodexSessionStore()
    @Published private(set) var snapshot = CodexSessionSnapshot()
    var onEvent: ((CodexSessionEvent) -> Void)?

    private let root: URL
    private let catalogURL: URL?
    private let queue = DispatchQueue(label: "Glance.codex-sessions", qos: .utility)
    private var reader: CodexSessionReader
    private var timer: Timer?
    private var reading = false
    private var baselineLoaded = false

    init(root: URL = CodexSessionReader.defaultRoot(),
         catalogURL: URL? = CodexSessionReader.defaultCatalogURL(),
         reader: CodexSessionReader = CodexSessionReader(),
         startsTimer: Bool = true) {
        self.root = root; self.catalogURL = catalogURL; self.reader = reader
        refresh()
        if startsTimer {
            timer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in self?.refresh() }
            timer?.tolerance = 1
        }
    }

    deinit { timer?.invalidate() }

    var sessions: [CodexSession] { snapshot.sessions }
    var activeCount: Int { snapshot.activeCount }
    var attentionCount: Int { snapshot.attentionCount }

    func refresh() {
        guard !reading else { return }
        reading = true
        queue.async { [weak self] in
            guard let self else { return }
            let next = self.reader.read(root: self.root, catalogURL: self.catalogURL)
            DispatchQueue.main.async {
                let previous = self.snapshot
                self.snapshot = next
                if self.baselineLoaded { self.emitTransitions(from: previous, to: next) }
                self.baselineLoaded = true
                self.reading = false
            }
        }
    }

    private func emitTransitions(from previous: CodexSessionSnapshot, to next: CodexSessionSnapshot) {
        let old = Dictionary(uniqueKeysWithValues: previous.sessions.map { ($0.id, $0) })
        for session in next.sessions {
            let prior = old[session.id]
            guard prior?.status != session.status else { continue }
            switch session.status {
            case .needsInput: onEvent?(.needsInput(session))
            case .needsApproval: onEvent?(.needsApproval(session))
            case .failed where prior?.status.isActive == true: onEvent?(.failed(session))
            case .ready where prior?.status.isActive == true
                || (prior == nil && session.updatedAt > previous.scannedAt): onEvent?(.ready(session))
            default: break
            }
        }
    }
}
