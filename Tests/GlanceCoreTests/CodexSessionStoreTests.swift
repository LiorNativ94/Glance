import Combine
import XCTest
@testable import Glance
@testable import GlanceCore

final class CodexSessionStoreTests: XCTestCase {
    func testOnlyEmitsCompletionAfterBaselineRunningState() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("session.jsonl")
        try write([meta(), event("task_started", second: 1)], to: file)

        let store = CodexSessionStore(root: root, catalogURL: nil,
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
