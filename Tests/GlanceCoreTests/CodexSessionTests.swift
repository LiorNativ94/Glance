import XCTest
@testable import GlanceCore

final class CodexSessionTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws { try FileManager.default.removeItem(at: root) }

    func testReadsRunningAndWaitingAgentsWithoutRetainingMessages() throws {
        try write("root.jsonl", [meta("root", cwd: "/tmp/Project One"), event("task_started", second: 1)])
        try write("agent.jsonl", [meta("agent", cwd: "/tmp/Project One", parent: "root", agent: "Turing"),
                                    event("task_started", second: 1), requestInput(second: 2)])

        let snapshot = CodexSessionReader().read(root: root, now: Date())

        XCTAssertEqual(snapshot.activeCount, 2)
        XCTAssertEqual(snapshot.attentionCount, 1)
        XCTAssertEqual(snapshot.sessions.first(where: { $0.id == "root" })?.status, .running)
        let agent = try XCTUnwrap(snapshot.sessions.first(where: { $0.id == "agent" }))
        XCTAssertEqual(agent.status, .needsInput)
        XCTAssertEqual(agent.agentName, "Turing")
        XCTAssertEqual(agent.parentID, "root")
        XCTAssertEqual(agent.project, "Project One")
        XCTAssertEqual(agent.deepLink?.absoluteString, "codex://threads/agent")
    }

    func testApprovalCompletionAndIncrementalAppendTransitions() throws {
        let url = try write("approval.jsonl", [meta("approval"), event("task_started", second: 1), approval(second: 2)])
        let reader = CodexSessionReader()
        XCTAssertEqual(reader.read(root: root).sessions.first?.status, .needsApproval)

        try append(output(second: 3), to: url)
        XCTAssertEqual(reader.read(root: root).sessions.first?.status, .running)

        try append(event("task_complete", second: 4), to: url)
        XCTAssertEqual(reader.read(root: root).sessions.first?.status, .ready)
    }

    func testGuardianReviewThreadsAreExcluded() throws {
        var guardian = meta("guardian")
        var payload = guardian["payload"] as! [String: Any]
        payload["thread_source"] = "guardian_review"
        guardian["payload"] = payload
        try write("guardian.jsonl", [guardian, event("task_started", second: 1)])
        XCTAssertTrue(CodexSessionReader().read(root: root).sessions.isEmpty)
    }

    @discardableResult private func write(_ name: String, _ values: [[String: Any]]) throws -> URL {
        let url = root.appendingPathComponent(name)
        let data = try values.map { try JSONSerialization.data(withJSONObject: $0) + Data([10]) }.reduce(Data(), +)
        try data.write(to: url)
        return url
    }

    private func append(_ value: [String: Any], to url: URL) throws {
        let handle = try FileHandle(forWritingTo: url)
        defer { try? handle.close() }
        try handle.seekToEnd()
        try handle.write(contentsOf: JSONSerialization.data(withJSONObject: value) + Data([10]))
    }

    private func meta(_ id: String, cwd: String = "/tmp/Glance", parent: String? = nil,
                      agent: String? = nil) -> [String: Any] {
        var payload: [String: Any] = ["id": id, "cwd": cwd, "originator": "Codex Desktop", "thread_source": parent == nil ? "user" : "subagent"]
        if let parent {
            payload["source"] = ["subagent": ["thread_spawn": ["parent_thread_id": parent, "agent_nickname": agent ?? "Agent"]]]
        }
        return ["timestamp": timestamp(0), "type": "session_meta", "payload": payload]
    }

    private func event(_ type: String, second: Int) -> [String: Any] {
        ["timestamp": timestamp(second), "type": "event_msg", "payload": ["type": type]]
    }

    private func requestInput(second: Int) -> [String: Any] {
        ["timestamp": timestamp(second), "type": "response_item",
         "payload": ["type": "function_call", "name": "request_user_input_async", "call_id": "input"]]
    }

    private func approval(second: Int) -> [String: Any] {
        let arguments = "{\"sandbox_permissions\":\"require_escalated\"}"
        return ["timestamp": timestamp(second), "type": "response_item",
                "payload": ["type": "function_call", "name": "exec_command", "call_id": "approval", "arguments": arguments]]
    }

    private func output(second: Int) -> [String: Any] {
        ["timestamp": timestamp(second), "type": "response_item",
         "payload": ["type": "function_call_output", "call_id": "approval"]]
    }

    private func timestamp(_ second: Int) -> String {
        ISO8601DateFormatter().string(from: Date().addingTimeInterval(Double(second)))
    }
}
