import Foundation
import CoreFoundation
import CryptoKit

public struct LocalActivityRecord: Identifiable, Equatable, Sendable {
    public let id: String
    public let date: Date
    public let model: String
    public let session: String
    public let project: String?
    /// Includes cached input; cached is a subset, never added again to total.
    public let input: Int
    public let cached: Int
    public let output: Int
    public var total: Int { input + output }
    public var uncachedInput: Int { max(0, input - cached) }
    public var excludingCache: Int { uncachedInput + output }
}

public struct LocalActivityAggregate: Identifiable, Equatable, Sendable {
    public let id: String
    public var input: Int = 0
    public var cached: Int = 0
    public var output: Int = 0
    public var total: Int { input + output }
    public var uncachedInput: Int { max(0, input - cached) }
    public var excludingCache: Int { uncachedInput + output }
}

public struct LocalActivityReport: Sendable {
    public enum Grouping { case model, session, project, day }
    public let records: [LocalActivityRecord]
    public let skippedCount: Int
    public let unattributedCount: Int
    public let isPartial: Bool
    public let scannedAt: Date

    public init(records: [LocalActivityRecord] = [], skippedCount: Int = 0,
                unattributedCount: Int = 0, isPartial: Bool = false, scannedAt: Date = .now) {
        self.records = records; self.skippedCount = skippedCount
        self.unattributedCount = unattributedCount; self.isPartial = isPartial; self.scannedAt = scannedAt
    }

    public func aggregates(by grouping: Grouping, since: Date = .distantPast,
                           calendar: Calendar = .current) -> [LocalActivityAggregate] {
        var values: [String: LocalActivityAggregate] = [:]
        for record in records where record.date >= since {
            let key: String
            switch grouping {
            case .model: key = record.model
            case .session: key = record.session
            case .project: key = record.project ?? "Unknown project"
            case .day:
                let parts = calendar.dateComponents([.year, .month, .day], from: record.date)
                key = String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
            }
            var value = values[key] ?? LocalActivityAggregate(id: key)
            value.input += record.input; value.cached += record.cached; value.output += record.output
            values[key] = value
        }
        return values.values.sorted { $0.total == $1.total ? $0.id < $1.id : $0.total > $1.total }
    }
}

/// Serial, bounded reader. Cache contains usage metadata only, never prompts or message content.
/// Run off the main thread; reuse an instance to read only appended bytes on subsequent refreshes.
public final class LocalActivityReader {
    private struct Counts: Equatable {
        var input: Int; var cached: Int; var output: Int
        static let zero = Counts(input: 0, cached: 0, output: 0)
        func delta(from previous: Counts) -> Counts {
            Counts(input: max(0, input - previous.input), cached: max(0, cached - previous.cached),
                   output: max(0, output - previous.output))
        }
    }
    private struct Event {
        var date: Date; var model: String; var session: String; var project: String?
        var counts: Counts; var cumulative: Bool; var key: String; var sidechain: Bool
    }
    private struct FileCache {
        var identity: String = ""
        var size: UInt64 = 0
        var modified: Date = .distantPast
        var offset: UInt64 = 0
        var checkpoint = Data()
        var prefix = Data()
        var prefixLength = 0
        var events: [Event] = []
        var eventIndices: [String: Int] = [:]
        var baseline: Event?
        var nextEventOrdinal = 0
        var evicted = 0
        var session: String = ""
        var parent: String?
        var forkDate: Date?
        var model: String = "Unknown model"
        var project: String?
        var metadataSeen = false
        var unresolvedOrigin = false
        var skipped = 0
        var oversizedLine = false
    }
    private var cache: [String: FileCache] = [:]
    private var retainedSince: [SubscriptionProvider: Date] = [:]
    private let maxBytesPerRead: Int
    private let maxLineBytes = 1_048_576
    private let maxFiles = 2_000
    private let maxEvents: Int
    private let formatter = ISO8601DateFormatter()
    private let fractionalFormatter: ISO8601DateFormatter = {
        let value = ISO8601DateFormatter(); value.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return value
    }()

    public init(maxBytesPerRead: Int = 32 * 1_024 * 1_024, maxRetainedEvents: Int = 100_000) {
        self.maxBytesPerRead = max(1, maxBytesPerRead)
        self.maxEvents = max(1, maxRetainedEvents)
    }

    public static func defaultRoots(provider: SubscriptionProvider,
                                    environment: [String: String] = ProcessInfo.processInfo.environment,
                                    homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser) -> [URL] {
        func root(_ key: String, fallback: String) -> URL {
            guard let override = environment[key], !override.isEmpty else {
                return homeDirectory.appendingPathComponent(fallback)
            }
            return URL(fileURLWithPath: (override as NSString).expandingTildeInPath)
        }
        switch provider {
        case .codex:
            let base = root("CODEX_HOME", fallback: ".codex")
            return [base.appendingPathComponent("sessions"), base.appendingPathComponent("archived_sessions")]
        case .claude:
            if environment["CLAUDE_CONFIG_DIR"]?.isEmpty == false {
                return [root("CLAUDE_CONFIG_DIR", fallback: ".claude").appendingPathComponent("projects")]
            }
            return [homeDirectory.appendingPathComponent(".claude/projects"),
                    homeDirectory.appendingPathComponent(".config/claude/projects")]
        }
    }

    public func read(provider: SubscriptionProvider, roots: [URL], since: Date) -> LocalActivityReport {
        var files: [URL] = [], seen = Set<String>(), partial = false, discoverySkipped = 0
        for root in roots {
            guard FileManager.default.fileExists(atPath: root.path) else { continue }
            guard let enumerator = FileManager.default.enumerator(at: root,
                includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey, .contentModificationDateKey],
                options: [.skipsHiddenFiles], errorHandler: { _, _ in discoverySkipped += 1; return true }) else {
                discoverySkipped += 1; continue
            }
            for case let file as URL in enumerator {
                guard files.count < maxFiles else { partial = true; break }
                guard file.pathExtension == "jsonl",
                      let metadata = try? file.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .contentModificationDateKey]),
                      metadata.isRegularFile == true, metadata.isSymbolicLink != true,
                      (metadata.contentModificationDate ?? .distantFuture) >= since,
                      seen.insert(file.standardizedFileURL.path).inserted else { continue }
                files.append(file)
            }
        }
        // Recent active sessions get the first bounded scan budget; older files continue next refresh.
        files.sort {
            let lhs = (try? $0.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
            let rhs = (try? $1.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
            return lhs == rhs ? $0.path < $1.path : lhs > rhs
        }
        let prefix = provider.rawValue + ":"
        if let previousSince = retainedSince[provider], since < previousSince {
            cache = cache.filter { !$0.key.hasPrefix(prefix) }
        }
        retainedSince[provider] = since
        let active = Set(files.map { prefix + $0.path })
        cache = cache.filter { !$0.key.hasPrefix(prefix) || active.contains($0.key) }
        var budget = maxBytesPerRead
        let perFileLimit = max(1, maxEvents / max(1, files.count))
        for file in files {
            let key = prefix + file.path
            guard budget > 0 else { partial = true; break }
            do {
                var state = cache[key] ?? FileCache()
                try scan(file: file, state: &state, provider: provider, budget: &budget,
                         eventLimit: perFileLimit, since: since)
                if state.offset < state.size { partial = true }
                cache[key] = state
            } catch { discoverySkipped += 1 }
        }
        let states = files.compactMap { file -> (String, FileCache)? in
            cache[prefix + file.path].map { (file.path, $0) }
        }
        var skipped = discoverySkipped + states.reduce(0) { $0 + $1.1.skipped + $1.1.evicted }
        let records: [LocalActivityRecord]
        if provider == .claude {
            records = claudeRecords(states: states, since: since)
        } else {
            records = codexRecords(states: states, since: since, skipped: &skipped)
        }
        let unattributed = records.filter { $0.model == "Unknown model" }.count
        return LocalActivityReport(records: records.sorted { $0.date < $1.date }, skippedCount: skipped,
            unattributedCount: unattributed, isPartial: partial || skipped > 0 || unattributed > 0, scannedAt: .now)
    }

    private func scan(file: URL, state: inout FileCache, provider: SubscriptionProvider,
                      budget: inout Int, eventLimit: Int, since: Date) throws {
        let attributes = try FileManager.default.attributesOfItem(atPath: file.path)
        let size = (attributes[.size] as? NSNumber)?.uint64Value ?? 0
        let modified = attributes[.modificationDate] as? Date ?? .distantPast
        let identity = "\(attributes[.systemNumber] ?? ""):\(attributes[.systemFileNumber] ?? "")"
        let handle = try FileHandle(forReadingFrom: file)
        defer { try? handle.close() }
        let prefix = try handle.read(upToCount: Int(min(size, 256))) ?? Data()
        var rewritten = state.identity != identity || size < state.offset
            || (size == state.size && modified != state.modified)
        if !state.prefix.isEmpty && Data(SHA256.hash(data: prefix.prefix(state.prefixLength))) != state.prefix {
            rewritten = true
        }
        if state.offset > 0 && !state.checkpoint.isEmpty {
            let count = Int(min(state.offset, 256))
            try handle.seek(toOffset: state.offset - UInt64(count))
            let tail = try handle.read(upToCount: count) ?? Data()
            if Data(SHA256.hash(data: tail)) != state.checkpoint { rewritten = true }
        }
        if rewritten { state = FileCache() }
        state.identity = identity; state.size = size; state.modified = modified
        state.prefix = Data(SHA256.hash(data: prefix)); state.prefixLength = prefix.count
        if state.session.isEmpty { state.session = file.deletingPathExtension().lastPathComponent }
        compact(&state, provider: provider, since: since, limit: eventLimit)
        try handle.seek(toOffset: state.offset)
        var pending = Data(), position = state.offset
        while budget > 0 || !pending.isEmpty {
            let chunk = try handle.read(upToCount: budget > 0 ? min(65_536, budget) : 65_536) ?? Data()
            if chunk.isEmpty { break }
            budget -= chunk.count
            for byte in chunk {
                position += 1
                if byte == 10 {
                    if state.oversizedLine { state.oversizedLine = false }
                    else if !pending.isEmpty { parse(pending, state: &state, provider: provider, path: file.path) }
                    pending.removeAll(keepingCapacity: true)
                    state.offset = position
                } else if !state.oversizedLine {
                    pending.append(byte)
                    if pending.count > maxLineBytes {
                        pending.removeAll(keepingCapacity: true); state.oversizedLine = true; state.skipped += 1
                    }
                }
            }
            compact(&state, provider: provider, since: since, limit: eventLimit)
            if state.oversizedLine { state.offset = position }
        }
        // An unfinished final line is retried from its beginning after the writer appends a newline.
        try handle.seek(toOffset: state.offset - min(state.offset, 256))
        let tail = try handle.read(upToCount: Int(min(state.offset, 256))) ?? Data()
        state.checkpoint = Data(SHA256.hash(data: tail))
    }

    private func compact(_ state: inout FileCache, provider: SubscriptionProvider, since: Date, limit: Int) {
        // Preserve file order: the folded prefix supplies the counter preceding retained usage.
        let expiredPrefix = state.events.prefix(while: { $0.date < since }).count
        let removeCount = max(expiredPrefix, max(0, state.events.count - limit))
        guard removeCount > 0 else { return }
        for event in state.events.prefix(removeCount) {
            if event.date >= since { state.evicted += 1 }
            if provider == .codex {
                if event.key == state.baseline?.key { continue }
                var counts = state.baseline?.counts ?? .zero
                if event.cumulative {
                    if event.counts.input >= counts.input && event.counts.output >= counts.output {
                        counts = event.counts
                    }
                } else {
                    counts.input += event.counts.input; counts.cached += event.counts.cached
                    counts.output += event.counts.output
                }
                var baseline = event; baseline.counts = counts; baseline.cumulative = true
                state.baseline = baseline
            }
        }
        state.events.removeFirst(removeCount)
        if provider == .claude {
            state.eventIndices = Dictionary(uniqueKeysWithValues: state.events.enumerated().map { ($0.element.key, $0.offset) })
        }
    }

    private func parse(_ data: Data, state: inout FileCache, provider: SubscriptionProvider, path: String) {
        guard let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            state.skipped += 1; return
        }
        let type = root["type"] as? String
        let date = (root["timestamp"] as? String).flatMap(parseDate)
        if provider == .claude {
            guard type == "assistant", let message = root["message"] as? [String: Any],
                  let usage = message["usage"] as? [String: Any] else { return }
            guard validUsage(usage, keys: ["input_tokens", "output_tokens", "cache_creation_input_tokens", "cache_read_input_tokens"]) else {
                state.skipped += 1; return
            }
            guard let date else { state.skipped += 1; return }
            let session = text(root["sessionId"]) ?? text(root["session_id"])
                ?? text((root["metadata"] as? [String: Any])?["sessionId"])
                ?? text((message["metadata"] as? [String: Any])?["sessionId"]) ?? state.session
            let model = text(message["model"]) ?? "Unknown model"
            let cached = count(usage["cache_read_input_tokens"])
            let counts = Counts(input: count(usage["input_tokens"]) + count(usage["cache_creation_input_tokens"]) + cached,
                                cached: cached, output: count(usage["output_tokens"]))
            let key: String
            if let messageID = text(message["id"]), let requestID = text(root["requestId"]) {
                key = messageID + ":" + requestID
            } else { key = path + ":" + String(state.nextEventOrdinal) }
            state.nextEventOrdinal += 1
            let event = Event(date: date, model: model, session: session, project: text(root["cwd"]),
                              counts: counts, cumulative: false, key: key, sidechain: root["isSidechain"] as? Bool == true)
            if let index = state.eventIndices[key] { state.events[index] = event }
            else { state.eventIndices[key] = state.events.count; state.events.append(event) }
        } else {
            let payload = root["payload"] as? [String: Any] ?? [:]
            if type == "session_meta" {
                guard !state.metadataSeen else { return }
                state.metadataSeen = true
                state.session = text(payload["id"]) ?? text(root["id"]) ?? text(payload["session_id"])
                    ?? text(payload["sessionId"]) ?? state.session
                state.parent = text(payload["forked_from_id"]) ?? text(payload["forkedFromId"])
                    ?? text(payload["parent_session_id"]) ?? text(payload["parentSessionId"])
                state.unresolvedOrigin = (payload["source"] as? [String: Any])?["subagent"] != nil && state.parent == nil
                state.forkDate = (payload["timestamp"] as? String).flatMap(parseDate) ?? date
                state.project = text(payload["cwd"])
                return
            }
            let info = payload["info"] as? [String: Any] ?? [:]
            if type == "turn_context" {
                let candidates = [payload["model"], payload["model_name"], info["model"], info["model_name"]]
                if candidates.contains(where: { $0 != nil }) {
                    state.model = candidates.compactMap(text).first ?? "Unknown model"
                }
                state.project = text(payload["cwd"]) ?? text(payload["current_working_directory"])
                    ?? text(payload["currentWorkingDirectory"]) ?? state.project
                return
            }
            guard type == "event_msg", payload["type"] as? String == "token_count" else { return }
            guard let date else { state.skipped += 1; return }
            let total = info["total_token_usage"] as? [String: Any]
            guard let usage = total ?? info["last_token_usage"] as? [String: Any] else { return }
            guard validUsage(usage, keys: ["input_tokens", "output_tokens", "cached_input_tokens", "cache_read_input_tokens"]) else {
                state.skipped += 1; return
            }
            let model = state.model != "Unknown model" ? state.model
                : text(info["model"]) ?? text(info["model_name"]) ?? text(payload["model"])
                    ?? text(root["model"]) ?? "Unknown model"
            let input = count(usage["input_tokens"])
            let counts = Counts(input: input,
                cached: min(input, max(count(usage["cached_input_tokens"]), count(usage["cache_read_input_tokens"]))),
                output: count(usage["output_tokens"]))
            let key = "\(date.timeIntervalSince1970):\(counts.input):\(counts.cached):\(counts.output)"
            state.events.append(Event(date: date, model: model, session: state.session, project: state.project,
                                      counts: counts, cumulative: total != nil, key: key, sidechain: false))
        }
    }

    private func claudeRecords(states: [(String, FileCache)], since: Date) -> [LocalActivityRecord] {
        var winners: [String: (String, Event)] = [:]
        for (path, state) in states {
            for event in state.events {
                if let (otherPath, other) = winners[event.key] {
                    if event.sidechain != other.sidechain { if event.sidechain { continue } }
                    else if path.contains("/subagents/") != otherPath.contains("/subagents/") {
                        if path.contains("/subagents/") { continue }
                    } else if path > otherPath { continue }
                }
                winners[event.key] = (path, event)
            }
        }
        return winners.values.compactMap { _, event in
            guard event.date >= since, event.counts.input + event.counts.output > 0 else { return nil }
            return record(event, counts: event.counts, id: event.key)
        }
    }

    private func codexRecords(states: [(String, FileCache)], since: Date, skipped: inout Int) -> [LocalActivityRecord] {
        var sessions: [String: FileCache] = [:]
        for (_, state) in states {
            if state.events.count > (sessions[state.session]?.events.count ?? -1) { sessions[state.session] = state }
        }
        var result: [LocalActivityRecord] = []
        for state in sessions.values {
            if state.unresolvedOrigin { skipped += state.events.count; continue }
            var previous = state.baseline?.counts ?? .zero
            if let parent = state.parent {
                guard let forkDate = state.forkDate, let parentState = sessions[parent],
                      let baseline = ((parentState.baseline.map { [$0] } ?? []) + parentState.events)
                        .last(where: { $0.cumulative && $0.date <= forkDate }) else {
                    skipped += state.events.count; continue
                }
                previous = Counts(input: max(previous.input, baseline.counts.input),
                                  cached: max(previous.cached, baseline.counts.cached),
                                  output: max(previous.output, baseline.counts.output))
            }
            var seen = Set<String>()
            var needsTruncatedBaseline = !state.metadataSeen && state.baseline == nil
            for event in state.events {
                if state.parent != nil, let forkDate = state.forkDate, event.date <= forkDate { continue }
                guard seen.insert(event.key).inserted else { continue }
                if needsTruncatedBaseline && event.cumulative {
                    previous = event.counts; needsTruncatedBaseline = false; skipped += 1; continue
                }
                let delta: Counts
                if event.cumulative {
                    if event.counts.input < previous.input || event.counts.output < previous.output {
                        skipped += 1; continue
                    }
                    // Replayed or interleaved lower snapshots never reset the counted watermark.
                    delta = event.counts.delta(from: previous)
                    previous = Counts(input: max(previous.input, event.counts.input),
                                      cached: max(previous.cached, event.counts.cached),
                                      output: max(previous.output, event.counts.output))
                } else {
                    // Without a counter a fork cannot establish whether this is copied history.
                    if state.parent != nil { skipped += 1; continue }
                    delta = event.counts
                    previous.input += delta.input; previous.cached += delta.cached; previous.output += delta.output
                }
                guard event.date >= since, delta.input + delta.output > 0 else { continue }
                result.append(record(event, counts: delta, id: state.session + ":" + event.key))
            }
        }
        return result
    }

    private func record(_ event: Event, counts: Counts, id: String) -> LocalActivityRecord {
        LocalActivityRecord(id: id, date: event.date, model: event.model, session: event.session,
            project: event.project, input: counts.input, cached: min(counts.input, counts.cached), output: counts.output)
    }
    private func count(_ value: Any?) -> Int {
        guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID(),
              number.doubleValue.isFinite, number.doubleValue > 0 else { return 0 }
        return Int(min(number.doubleValue, 1_000_000_000_000))
    }
    private func validUsage(_ usage: [String: Any], keys: [String]) -> Bool {
        let present = keys.compactMap { usage[$0] }
        return (usage["input_tokens"] != nil || usage["output_tokens"] != nil) && !present.isEmpty && present.allSatisfy {
            guard let number = $0 as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID() else { return false }
            return number.doubleValue.isFinite && number.doubleValue >= 0 && number.doubleValue <= 1_000_000_000_000
        }
    }
    private func text(_ value: Any?) -> String? {
        guard let text = value as? String else { return nil }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : String(trimmed.prefix(1_024))
    }
    private func parseDate(_ value: String) -> Date? {
        fractionalFormatter.date(from: value) ?? formatter.date(from: value)
    }
}
