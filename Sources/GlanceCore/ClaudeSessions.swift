import Foundation

/// Reads the registry Claude Code keeps for each open session. Only live processes are reported, and prompts are never read.
public struct ClaudeSessionReader {
    public init() {}

    public static func defaultRoot(environment: [String: String] = ProcessInfo.processInfo.environment,
                                   homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser) -> URL {
        let base = environment["CLAUDE_CONFIG_DIR"].flatMap { $0.isEmpty ? nil : $0 }
            .map { URL(fileURLWithPath: ($0 as NSString).expandingTildeInPath) }
            ?? homeDirectory.appendingPathComponent(".claude")
        return base.appendingPathComponent("sessions")
    }

    public func read(root: URL, now: Date = .now,
                     isAlive: (Int32) -> Bool = { kill($0, 0) == 0 || errno == EPERM }) -> AgentSessionSnapshot {
        guard let files = try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil,
                                                                       options: [.skipsHiddenFiles]) else {
            return AgentSessionSnapshot(scannedAt: now, error: "Claude Code session records were not found on this Mac.")
        }
        var byID: [String: AgentSession] = [:]
        for file in files where file.pathExtension == "json" {
            guard let data = try? Data(contentsOf: file),
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let id = text(object["sessionId"]), let cwd = text(object["cwd"]),
                  let pid = (object["pid"] as? NSNumber)?.int32Value, pid > 0,
                  object["spare"] as? Bool != true, isAlive(pid) else { continue }
            let updated = date(object["statusUpdatedAt"]) ?? date(object["updatedAt"]) ?? date(object["startedAt"]) ?? now
            let status = status(text(object["status"]), waitingFor: text(object["waitingFor"]))
            // Desktop sessions carry a host ID Claude accepts in its continue link; terminal sessions have none.
            let link = text(object["hostSessionId"])
                .flatMap { $0.range(of: "^local_[A-Za-z0-9-]{1,64}$", options: .regularExpression) == nil ? nil : $0 }
                .flatMap { URL(string: "claude://code/continue?session=\($0)") }
            let session = AgentSession(id: id, title: text(object["name"]).map { String($0.prefix(160)) } ?? "Claude session",
                project: URL(fileURLWithPath: cwd).lastPathComponent, workingDirectory: cwd, status: status,
                startedAt: status.isActive ? updated : nil, updatedAt: updated,
                agentName: text(object["entrypoint"]) == "cli" ? "Terminal" : nil, deepLink: link)
            if let previous = byID[id], previous.updatedAt >= session.updatedAt { continue }
            byID[id] = session
        }
        let sessions = byID.values.sorted {
            if $0.status.isActive != $1.status.isActive { return $0.status.isActive }
            return $0.updatedAt == $1.updatedAt ? $0.id < $1.id : $0.updatedAt > $1.updatedAt
        }
        return AgentSessionSnapshot(sessions: sessions, scannedAt: now)
    }

    private func status(_ value: String?, waitingFor: String?) -> AgentSessionStatus {
        switch value {
        case "busy": return .running
        case "waiting": return waitingFor?.hasSuffix("request") == true ? .needsApproval : .needsInput
        default: return .ready
        }
    }

    private func date(_ value: Any?) -> Date? {
        (value as? NSNumber).map { Date(timeIntervalSince1970: $0.doubleValue / 1_000) }
    }

    private func text(_ value: Any?) -> String? {
        guard let value = (value as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else { return nil }
        return value
    }
}
