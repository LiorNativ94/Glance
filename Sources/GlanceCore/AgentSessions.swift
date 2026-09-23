import Foundation

public enum AgentSessionStatus: String, Equatable, Sendable {
    case running
    case needsInput
    case needsApproval
    case ready
    case failed

    public var isActive: Bool {
        switch self {
        case .running, .needsInput, .needsApproval: return true
        case .ready, .failed: return false
        }
    }

    public var needsAttention: Bool { self == .needsInput || self == .needsApproval }
}

public struct AgentSession: Identifiable, Equatable, Sendable {
    public let id: String
    public let title: String
    public let project: String
    public let workingDirectory: String
    public let status: AgentSessionStatus
    public let startedAt: Date?
    public let updatedAt: Date
    public let parentID: String?
    public let agentName: String?
    /// Opens this exact session in its app; nil when the session has no app to open, such as a terminal session.
    public let deepLink: URL?

    public init(id: String, title: String, project: String, workingDirectory: String,
                status: AgentSessionStatus, startedAt: Date? = nil, updatedAt: Date,
                parentID: String? = nil, agentName: String? = nil, deepLink: URL? = nil) {
        self.id = id; self.title = title; self.project = project
        self.workingDirectory = workingDirectory; self.status = status
        self.startedAt = startedAt; self.updatedAt = updatedAt
        self.parentID = parentID; self.agentName = agentName; self.deepLink = deepLink
    }
}

public struct AgentSessionSnapshot: Equatable, Sendable {
    public let sessions: [AgentSession]
    public let scannedAt: Date
    public let error: String?

    public init(sessions: [AgentSession] = [], scannedAt: Date = .now, error: String? = nil) {
        self.sessions = sessions; self.scannedAt = scannedAt; self.error = error
    }

    public var activeCount: Int { sessions.count { $0.status.isActive } }
    public var attentionCount: Int { sessions.count { $0.status.needsAttention } }
}
