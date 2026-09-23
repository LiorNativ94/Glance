import Combine
import XCTest
@testable import Glance
@testable import GlanceCore

final class AgentSessionStoreTests: XCTestCase {
    func testGroupsUseLatestInteractionBeforeProjectNameOrActiveStatus() {
        let old = Date(timeIntervalSince1970: 100)
        let middle = Date(timeIntervalSince1970: 200)
        let latest = Date(timeIntervalSince1970: 300)
        let sessions = [
            AgentSession(id: "alpha", title: "Alpha", project: "Alpha", workingDirectory: "/Alpha",
                         status: .running, updatedAt: old),
            AgentSession(id: "beta-old", title: "Beta old", project: "Beta", workingDirectory: "/Beta",
                         status: .running, updatedAt: old),
            AgentSession(id: "beta-new", title: "Beta new", project: "Beta", workingDirectory: "/Beta",
                         status: .ready, updatedAt: latest),
            AgentSession(id: "zeta", title: "Zeta", project: "Zeta", workingDirectory: "/Zeta",
                         status: .ready, updatedAt: middle)
        ]

        let groups = SubscriptionDetails.groupedSessions(sessions)

        XCTAssertEqual(groups.map(\.project), ["Beta", "Zeta", "Alpha"])
        XCTAssertEqual(groups.first?.sessions.map(\.id), ["beta-new", "beta-old"])
    }

    func testOnlyEmitsCompletionAfterBaselineRunningState() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("session.jsonl")
        try write([meta(), event("task_started", second: 1)], to: file)

        let store = AgentSessionStore.codex(root: root, catalogURL: nil,
                                             reader: CodexSessionReader(maxFiles: 5), startsTimer: false)
        let baseline = expectation(description: "baseline")
        var cancellables = Set<AnyCancellable>()
        store.$snapshot.dropFirst().sink { snapshot in
            if snapshot.sessions.first?.status == .running { baseline.fulfill() }
        }.store(in: &cancellables)
        wait(for: [baseline], timeout: 2)

        let completion = expectation(description: "completion")
        store.onEvent = { transition in
            if case .ready(let session) = transition, session.id == "session" { completion.fulfill() }
        }
        try append(event("task_complete", second: 2), to: file)
        store.refresh()
        wait(for: [completion], timeout: 2)
    }

    func testClaudeReportsFinishedTurnsAndQuestionsButNotNewlyOpenedSessions() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        func record(_ id: String, _ status: String) throws {
            let object: [String: Any] = ["pid": Int(ProcessInfo.processInfo.processIdentifier), "sessionId": id,
                                         "cwd": "/tmp/Glance", "status": status,
                                         "statusUpdatedAt": Int(Date().timeIntervalSince1970 * 1_000)]
            try JSONSerialization.data(withJSONObject: object).write(to: root.appendingPathComponent(id + ".json"))
        }
        try record("working", "busy")
        let store = AgentSessionStore.claude(root: root, startsTimer: false)
        var events: [AgentSessionEvent] = []
        store.onEvent = { events.append($0) }
        func scan() {
            let done = expectation(description: "scan")
            var cancellables = Set<AnyCancellable>()
            store.$snapshot.dropFirst().sink { _ in done.fulfill() }.store(in: &cancellables)
            store.refresh()
            wait(for: [done], timeout: 2)
        }
        scan()
        XCTAssertTrue(events.isEmpty)

        try record("working", "waiting"); try record("opened", "idle")
        scan()
        XCTAssertEqual(events.map(\.kind), ["needsInput:working"])

        try record("working", "idle")
        scan()
        XCTAssertEqual(events.map(\.kind), ["needsInput:working", "ready:working"])
    }

    private func meta() -> [String: Any] {
        ["timestamp": timestamp(0), "type": "session_meta",
         "payload": ["id": "session", "cwd": "/tmp/Glance", "originator": "Codex Desktop", "thread_source": "user"]]
    }

    private func event(_ type: String, second: Int) -> [String: Any] {
        ["timestamp": timestamp(second), "type": "event_msg", "payload": ["type": type]]
    }

    private func write(_ values: [[String: Any]], to url: URL) throws {
        let data = try values.map { try JSONSerialization.data(withJSONObject: $0) + Data([10]) }.reduce(Data(), +)
        try data.write(to: url)
    }

    private func append(_ value: [String: Any], to url: URL) throws {
        let handle = try FileHandle(forWritingTo: url)
        defer { try? handle.close() }
        try handle.seekToEnd()
        try handle.write(contentsOf: JSONSerialization.data(withJSONObject: value) + Data([10]))
    }

    private func timestamp(_ second: Int) -> String {
        ISO8601DateFormatter().string(from: Date().addingTimeInterval(Double(second)))
    }
}

private extension AgentSessionEvent {
    var kind: String {
        switch self {
        case .ready(let session): return "ready:" + session.id
        case .needsInput(let session): return "needsInput:" + session.id
        case .needsApproval(let session): return "needsApproval:" + session.id
        case .failed(let session): return "failed:" + session.id
        }
    }
}
