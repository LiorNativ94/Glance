import XCTest
@testable import GlanceCore

final class ClaudeSessionTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws { try FileManager.default.removeItem(at: root) }

    func testMapsLiveRegistryStatusesAndLinksDesktopSessions() throws {
        try write(pid: 11, ["sessionId": "busy", "cwd": "/tmp/Project One", "name": "Fix login", "status": "busy",
                            "statusUpdatedAt": 3_000, "entrypoint": "claude-desktop", "hostSessionId": "local_abc-123"])
        try write(pid: 12, ["sessionId": "asking", "cwd": "/tmp/Project One", "status": "waiting",
                            "waitingFor": "input needed", "statusUpdatedAt": 2_000, "entrypoint": "cli"])
        try write(pid: 13, ["sessionId": "sandbox", "cwd": "/tmp/Two", "status": "waiting",
                            "waitingFor": "sandbox request", "statusUpdatedAt": 1_000])
        try write(pid: 14, ["sessionId": "idle", "cwd": "/tmp/Two", "name": "Review", "status": "idle",
                            "statusUpdatedAt": 4_000, "hostSessionId": "not a local id"])

        let snapshot = ClaudeSessionReader().read(root: root, isAlive: { _ in true })
        let byID = Dictionary(uniqueKeysWithValues: snapshot.sessions.map { ($0.id, $0) })

        XCTAssertEqual(snapshot.sessions.map(\.id), ["busy", "asking", "sandbox", "idle"])
        XCTAssertEqual(snapshot.activeCount, 3)
        XCTAssertEqual(snapshot.attentionCount, 2)
        XCTAssertEqual(byID["busy"]?.status, .running)
        XCTAssertEqual(byID["busy"]?.title, "Fix login")
        XCTAssertEqual(byID["busy"]?.project, "Project One")
        XCTAssertEqual(byID["busy"]?.startedAt, Date(timeIntervalSince1970: 3))
        XCTAssertEqual(byID["busy"]?.deepLink?.absoluteString, "claude://code/continue?session=local_abc-123")
        XCTAssertEqual(byID["asking"]?.status, .needsInput)
        XCTAssertEqual(byID["asking"]?.title, "Claude session")
        XCTAssertEqual(byID["asking"]?.agentName, "Terminal")
        XCTAssertNil(byID["asking"]?.deepLink)
        XCTAssertEqual(byID["sandbox"]?.status, .needsApproval)
        XCTAssertEqual(byID["idle"]?.status, .ready)
        XCTAssertNil(byID["idle"]?.startedAt)
        XCTAssertNil(byID["idle"]?.deepLink)
    }

    func testSkipsExitedProcessesSpareProcessesAndMalformedRecords() throws {
        try write(pid: 21, ["sessionId": "exited", "cwd": "/tmp/A", "status": "busy"])
        try write(pid: 22, ["sessionId": "spare", "cwd": "/tmp/A", "status": "idle", "spare": true])
        try write(pid: 23, ["cwd": "/tmp/A", "status": "busy"])
        try write(pid: 24, ["sessionId": "live", "cwd": "/tmp/A", "status": "idle"])
        try Data("not json".utf8).write(to: root.appendingPathComponent("25.json"))
        try Data("key".utf8).write(to: root.appendingPathComponent("24.abc.key"))

        let sessions = ClaudeSessionReader().read(root: root, isAlive: { $0 != 21 }).sessions

        XCTAssertEqual(sessions.map(\.id), ["live"])
    }

    func testReportsMissingRegistry() {
        let snapshot = ClaudeSessionReader().read(root: root.appendingPathComponent("missing"))
        XCTAssertTrue(snapshot.sessions.isEmpty)
        XCTAssertNotNil(snapshot.error)
    }

    func testHonorsClaudeConfigDirectory() {
        XCTAssertEqual(ClaudeSessionReader.defaultRoot(environment: ["CLAUDE_CONFIG_DIR": "/tmp/custom"]).path,
                       "/tmp/custom/sessions")
        XCTAssertEqual(ClaudeSessionReader.defaultRoot(environment: [:], homeDirectory: URL(fileURLWithPath: "/Users/me")).path,
                       "/Users/me/.claude/sessions")
    }

    private func write(pid: Int, _ values: [String: Any]) throws {
        var object = values
        object["pid"] = pid
        try JSONSerialization.data(withJSONObject: object).write(to: root.appendingPathComponent("\(pid).json"))
    }
}
