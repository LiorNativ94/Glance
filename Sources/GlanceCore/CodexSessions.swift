import Foundation
import SQLite3

/// Bounded, incremental reader for Codex's local lifecycle records. It never retains prompts.
public final class CodexSessionReader {
    private struct State {
        var id = ""
        var cwd = ""
        var originator = ""
        var threadSource = ""
        var parentID: String?
        var agentName: String?
        var lifecycleSeen = false
        var status: AgentSessionStatus = .ready
        var startedAt: Date?
        var updatedAt: Date = .distantPast
        var pendingApprovals = Set<String>()
        var offset: UInt64 = 0
        var size: UInt64 = 0
    }
    private struct CatalogEntry { var title: String; var cwd: String? }

    private var cache: [String: State] = [:]
    private let maxFiles: Int
    private let initialTailBytes: Int
    private let formatter = ISO8601DateFormatter()
    private let fractionalFormatter: ISO8601DateFormatter = {
        let value = ISO8601DateFormatter(); value.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return value
    }()

    public init(maxFiles: Int = 100, initialTailBytes: Int = 1_024 * 1_024) {
        self.maxFiles = max(1, maxFiles); self.initialTailBytes = max(1_024, initialTailBytes)
    }

    public static func defaultRoot(environment: [String: String] = ProcessInfo.processInfo.environment,
                                   homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser) -> URL {
        let base = environment["CODEX_HOME"].flatMap { $0.isEmpty ? nil : $0 }
            .map { URL(fileURLWithPath: ($0 as NSString).expandingTildeInPath) }
            ?? homeDirectory.appendingPathComponent(".codex")
        return base.appendingPathComponent("sessions")
    }

    public static func defaultCatalogURL(environment: [String: String] = ProcessInfo.processInfo.environment,
                                         homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser) -> URL {
        defaultRoot(environment: environment, homeDirectory: homeDirectory)
            .deletingLastPathComponent().appendingPathComponent("sqlite/codex-dev.db")
    }

    public func read(root: URL, catalogURL: URL? = nil, now: Date = .now) -> AgentSessionSnapshot {
        let cutoff = now.addingTimeInterval(-24 * 60 * 60)
        guard FileManager.default.fileExists(atPath: root.path) else {
            return AgentSessionSnapshot(scannedAt: now, error: "Codex session records were not found on this Mac.")
        }
        var files: [(URL, Date)] = []
        guard let enumerator = FileManager.default.enumerator(at: root,
            includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles]) else {
            return AgentSessionSnapshot(scannedAt: now, error: "Codex session records could not be read.")
        }
        for case let file as URL in enumerator where file.pathExtension == "jsonl" {
            guard let values = try? file.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .contentModificationDateKey]),
                  values.isRegularFile == true, values.isSymbolicLink != true,
                  let modified = values.contentModificationDate, modified >= cutoff else { continue }
            files.append((file, modified))
        }
        files.sort { $0.1 == $1.1 ? $0.0.path < $1.0.path : $0.1 > $1.1 }
        files = Array(files.prefix(maxFiles))
        let activePaths = Set(files.map { $0.0.standardizedFileURL.path })
        cache = cache.filter { activePaths.contains($0.key) }
        for (file, modified) in files { scan(file: file, modified: modified) }

        let catalog = readCatalog(catalogURL, since: cutoff)
        var byID: [String: AgentSession] = [:]
        for state in cache.values where !state.id.isEmpty && state.lifecycleSeen && state.threadSource != "guardian_review" {
            guard state.originator.isEmpty || state.originator.localizedCaseInsensitiveContains("Codex") else { continue }
            let entry = catalog[state.id]
            let cwd = entry?.cwd?.nonempty ?? state.cwd
            let project = URL(fileURLWithPath: cwd).lastPathComponent.nonempty ?? "Unknown project"
            let fallback = state.agentName ?? (state.parentID == nil ? "Codex task" : "Sub-agent")
            let title = entry?.title.nonempty ?? fallback
            let session = AgentSession(id: state.id, title: title, project: project, workingDirectory: cwd,
                status: state.status, startedAt: state.startedAt, updatedAt: state.updatedAt,
                parentID: state.parentID, agentName: state.agentName,
                deepLink: URL(string: "codex://threads/\(state.id)"))
            if let previous = byID[state.id], previous.updatedAt >= session.updatedAt { continue }
            byID[state.id] = session
        }
        let sessions = byID.values.sorted {
            if $0.status.isActive != $1.status.isActive { return $0.status.isActive }
            return $0.updatedAt > $1.updatedAt
        }
        return AgentSessionSnapshot(sessions: sessions, scannedAt: now)
    }

    private func scan(file: URL, modified: Date) {
        let path = file.standardizedFileURL.path
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: path),
              let size = (attributes[.size] as? NSNumber)?.uint64Value,
              let handle = try? FileHandle(forReadingFrom: file) else { return }
        defer { try? handle.close() }
        var state = cache[path] ?? State()
        if size < state.offset { state = State() }
        if state.offset == 0 {
            let prefixSize = min(size, 64 * 1_024)
            if let prefix = try? handle.read(upToCount: Int(prefixSize)) { parseLines(prefix, into: &state, discardFirst: false) }
            let tailStart = size > UInt64(initialTailBytes) ? size - UInt64(initialTailBytes) : prefixSize
            if tailStart > prefixSize {
                try? handle.seek(toOffset: tailStart)
                if let tail = try? handle.readToEnd() { parseLines(tail, into: &state, discardFirst: true) }
            } else if size > prefixSize {
                try? handle.seek(toOffset: prefixSize)
                if let rest = try? handle.readToEnd() { parseLines(rest, into: &state, discardFirst: false) }
            }
        } else if size > state.offset {
            try? handle.seek(toOffset: state.offset)
            if let appended = try? handle.readToEnd() { parseLines(appended, into: &state, discardFirst: false) }
        }
        state.offset = size; state.size = size
        if state.updatedAt == .distantPast { state.updatedAt = modified }
        cache[path] = state
    }

    private func parseLines(_ data: Data, into state: inout State, discardFirst: Bool) {
        guard let text = String(data: data, encoding: .utf8) else { return }
        var lines = text.split(separator: "\n", omittingEmptySubsequences: true)
        if discardFirst, !lines.isEmpty { lines.removeFirst() }
        for line in lines {
            guard let data = line.data(using: .utf8),
                  let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }
            parse(root, into: &state)
        }
    }

    private func parse(_ root: [String: Any], into state: inout State) {
        let type = root["type"] as? String
        let payload = root["payload"] as? [String: Any] ?? [:]
        let date = (root["timestamp"] as? String).flatMap(parseDate)
        if type == "session_meta" {
            state.id = text(payload["id"]) ?? state.id
            state.cwd = text(payload["cwd"]) ?? state.cwd
            state.originator = text(payload["originator"]) ?? state.originator
            state.threadSource = text(payload["thread_source"]) ?? state.threadSource
            if let source = payload["source"] as? [String: Any],
               let subagent = source["subagent"] as? [String: Any] {
                if let spawn = subagent["thread_spawn"] as? [String: Any] {
                    state.parentID = text(spawn["parent_thread_id"])
                    state.agentName = text(spawn["agent_nickname"])
                        ?? text(spawn["agent_path"]).map { URL(fileURLWithPath: $0).lastPathComponent }
                }
            }
            if let date { state.updatedAt = max(state.updatedAt, date) }
            return
        }
        if type == "event_msg" {
            switch payload["type"] as? String {
            case "task_started":
                state.lifecycleSeen = true
                state.status = .running; state.startedAt = date; state.pendingApprovals.removeAll()
                if let date { state.updatedAt = max(state.updatedAt, date) }
            case "task_complete":
                state.lifecycleSeen = true
                if !state.status.needsAttention { state.status = .ready }
                state.pendingApprovals.removeAll()
                if let date { state.updatedAt = max(state.updatedAt, date) }
            case "turn_aborted", "error":
                state.lifecycleSeen = true
                state.status = .failed; state.pendingApprovals.removeAll()
                if let date { state.updatedAt = max(state.updatedAt, date) }
            case "item_completed":
                if let item = payload["item"] as? [String: Any], item["type"] as? String == "UserMessage",
                   let date {
                    if state.status == .needsInput { state.status = .running }
                    state.updatedAt = max(state.updatedAt, date)
                }
            default: break
            }
        } else if type == "response_item" {
            let itemType = payload["type"] as? String
            let callID = text(payload["call_id"])
            if itemType == "function_call",
               ["request_user_input", "request_user_input_async"].contains(text(payload["name"]) ?? ""),
               state.status.isActive {
                state.status = .needsInput
                if let date { state.updatedAt = max(state.updatedAt, date) }
            } else if (itemType == "function_call" || itemType == "custom_tool_call"),
                      isApprovalRequest(payload), let callID, state.status.isActive {
                state.pendingApprovals.insert(callID); state.status = .needsApproval
                if let date { state.updatedAt = max(state.updatedAt, date) }
            } else if (itemType == "function_call_output" || itemType == "custom_tool_call_output"),
                      let callID, state.pendingApprovals.remove(callID) != nil, state.pendingApprovals.isEmpty,
                      state.status == .needsApproval {
                state.status = .running
                if let date { state.updatedAt = max(state.updatedAt, date) }
            }
        }
    }

    private func isApprovalRequest(_ payload: [String: Any]) -> Bool {
        if let arguments = payload["arguments"] as? String,
           let data = arguments.data(using: .utf8),
           let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           object["sandbox_permissions"] as? String == "require_escalated" { return true }
        if let input = payload["input"] as? String,
           input.contains("\"sandbox_permissions\":\"require_escalated\"") { return true }
        return false
    }

    private func readCatalog(_ url: URL?, since: Date) -> [String: CatalogEntry] {
        guard let url, FileManager.default.fileExists(atPath: url.path) else { return [:] }
        var database: OpaquePointer?
        guard sqlite3_open_v2(url.path, &database, SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX, nil) == SQLITE_OK,
              let database else { return [:] }
        defer { sqlite3_close(database) }
        let sql = "SELECT thread_id, display_title, cwd FROM local_thread_catalog WHERE missing_candidate = 0 AND source_recency_at >= ? ORDER BY source_recency_at DESC"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK, let statement else { return [:] }
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_double(statement, 1, since.timeIntervalSince1970)
        var result: [String: CatalogEntry] = [:]
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let idBytes = sqlite3_column_text(statement, 0), let titleBytes = sqlite3_column_text(statement, 1) else { continue }
            let id = String(cString: idBytes)
            guard result[id] == nil else { continue }
            let title = String(String(cString: titleBytes).prefix(160))
            let cwd = sqlite3_column_text(statement, 2).map { String(cString: $0) }
            result[id] = CatalogEntry(title: title, cwd: cwd)
        }
        return result
    }

    private func text(_ value: Any?) -> String? { (value as? String)?.trimmingCharacters(in: .whitespacesAndNewlines).nonempty }
    private func parseDate(_ value: String) -> Date? { fractionalFormatter.date(from: value) ?? formatter.date(from: value) }
}

private extension String {
    var nonempty: String? { isEmpty ? nil : self }
}
