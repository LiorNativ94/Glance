import XCTest
@testable import GlanceCore

final class LocalActivityTests: XCTestCase {
    private var root: URL!
    private let start = Date(timeIntervalSince1970: 1_789_430_400)
    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { try FileManager.default.removeItem(at: root) }

    func testClaudeStreamingAndGlobalDuplicatesDoNotInflateModelTokens() throws {
        let first = claude(output: 10), final = claude(output: 30)
        try write("parent.jsonl", [first, final])
        var copy = final; copy["isSidechain"] = true
        try write("subagents/copy.jsonl", [copy])
        let report = LocalActivityReader().read(provider: .claude, roots: [root], since: start)
        XCTAssertEqual(report.records.count, 1)
        XCTAssertEqual(report.records.first?.input, 640)
        XCTAssertEqual(report.records.first?.cached, 500)
        XCTAssertEqual(report.records.first?.total, 670)
        XCTAssertEqual(report.aggregates(by: .model).first?.id, "claude-sonnet-test")
        XCTAssertEqual(report.aggregates(by: .project).first?.id, "/tmp/sample")
    }

    func testCodexCumulativeDeltasKeepCacheSubsetAndAttributeModelSwitch() throws {
        try write("session.jsonl", [meta("s"), context("model-a"), tokens(1000, output: 100, second: 2),
            tokens(1000, output: 100, second: 3), context("model-b"), tokens(1500, output: 150, second: 4),
            tokens(1200, output: 120, second: 5)])
        let report = LocalActivityReader().read(provider: .codex, roots: [root], since: start)
        XCTAssertEqual(report.records.count, 2)
        XCTAssertEqual(report.aggregates(by: .model).map(\.total), [1100, 550])
        XCTAssertEqual(report.records.reduce(0) { $0 + $1.total }, 1650)
        XCTAssertEqual(report.records.reduce(0) { $0 + $1.cached }, 750)
    }

    func testCacheReuseIsSeparateAndRepeatedCumulativeEventsAreNotAddedAgain() throws {
        var first = tokens(1000, output: 100, second: 2)
        var second = tokens(2000, output: 200, second: 3)
        for entry in [0, 1] {
            var event = entry == 0 ? first : second
            var payload = event["payload"] as! [String: Any]
            var info = payload["info"] as! [String: Any]
            var total = info["total_token_usage"] as! [String: Any]
            total["cached_input_tokens"] = entry == 0 ? 900 : 1800
            info["total_token_usage"] = total; payload["info"] = info; event["payload"] = payload
            if entry == 0 { first = event } else { second = event }
        }
        try write("session.jsonl", [meta("s"), context("model-a"), first, first, second, second])
        let reader = LocalActivityReader()
        for _ in 0..<2 {
            let report = reader.read(provider: .codex, roots: [root], since: start)
            let model = try XCTUnwrap(report.aggregates(by: .model).first)
            XCTAssertEqual(model.total, 2200)
            XCTAssertEqual(model.cached, 1800)
            XCTAssertEqual(model.uncachedInput, 200)
            XCTAssertEqual(model.output, 200)
            XCTAssertEqual(model.excludingCache, 400)
            XCTAssertEqual(model.excludingCache + model.cached, model.total)
        }
        let claudeReport = LocalActivityReader()
        try write("claude.jsonl", [claude(output: 30)])
        let claudeModel = try XCTUnwrap(claudeReport.read(provider: .claude, roots: [root], since: start).aggregates(by: .model).first)
        XCTAssertEqual(claudeModel.total, 670)
        XCTAssertEqual(claudeModel.cached, 500)
        XCTAssertEqual(claudeModel.excludingCache, 170, "Claude cache creation stays in uncached input; cache reads are separate")
    }

    func testForkSkipsCopiedPrefixAndMissingParentIsExplicitlyPartial() throws {
        try write("parent.jsonl", [meta("parent"), context("a"), tokens(1000, output: 100, second: 2)])
        try write("child.jsonl", [meta("child", parent: "parent", second: 3), context("b"),
            tokens(1000, output: 100, second: 2), tokens(1200, output: 120, second: 4)])
        try write("missing.jsonl", [meta("orphan", parent: "missing", second: 3), context("b"),
            tokens(9000, output: 900, second: 4)])
        let report = LocalActivityReader().read(provider: .codex, roots: [root], since: start)
        XCTAssertEqual(report.records.reduce(0) { $0 + $1.total }, 1320)
        XCTAssertEqual(report.records.first(where: { $0.session == "child" })?.total, 220)
        XCTAssertTrue(report.isPartial)
        XCTAssertEqual(report.skippedCount, 1)
    }

    func testAppendPartialLineAndRewriteReplaceCachedRows() throws {
        let reader = LocalActivityReader()
        let file = try write("claude.jsonl", [claude(output: 10)])
        XCTAssertEqual(reader.read(provider: .claude, roots: [root], since: start).records.first?.total, 650)
        let append = try JSONSerialization.data(withJSONObject: claude(output: 30))
        let handle = try FileHandle(forWritingTo: file)
        try handle.seekToEnd(); try handle.write(contentsOf: append); try handle.close()
        let partial = reader.read(provider: .claude, roots: [root], since: start)
        XCTAssertTrue(partial.isPartial)
        XCTAssertEqual(partial.records.first?.total, 650)
        let finish = try FileHandle(forWritingTo: file)
        try finish.seekToEnd(); try finish.write(contentsOf: Data([10])); try finish.close()
        XCTAssertEqual(reader.read(provider: .claude, roots: [root], since: start).records.first?.total, 670)
        try write("claude.jsonl", [claude(output: 5)])
        XCTAssertEqual(reader.read(provider: .claude, roots: [root], since: start).records.first?.total, 645)
    }

    func testSmallBudgetEventuallyAdvancesAndSinceFiltersAfterCumulativeAccounting() throws {
        try write("session.jsonl", [meta("s"), context("a"), tokens(1000, output: 100, second: 2),
                                  tokens(1200, output: 120, second: 4)])
        let reader = LocalActivityReader(maxBytesPerRead: 32)
        var report = LocalActivityReport()
        for _ in 0..<20 { report = reader.read(provider: .codex, roots: [root], since: start.addingTimeInterval(3)) }
        XCTAssertFalse(report.isPartial)
        XCTAssertEqual(report.records.first?.total, 220)
    }

    func testUnknownModelAndMalformedDataAreNotPresentedAsZeroOrKnownModel() throws {
        var row = claude(output: 10)
        var message = row["message"] as! [String: Any]; message.removeValue(forKey: "model"); row["message"] = message
        let file = try write("unknown.jsonl", [row])
        let handle = try FileHandle(forWritingTo: file)
        try handle.seekToEnd(); try handle.write(contentsOf: Data("malformed\n".utf8)); try handle.close()
        let report = LocalActivityReader().read(provider: .claude, roots: [root], since: start)
        XCTAssertEqual(report.unattributedCount, 1)
        XCTAssertEqual(report.skippedCount, 1)
        XCTAssertTrue(report.isPartial)
    }

    func testConfigurationOverridesAndArchivedCodexRoots() {
        XCTAssertEqual(LocalActivityReader.defaultRoots(provider: .codex,
            environment: ["CODEX_HOME": "/tmp/custom"], homeDirectory: root).map(\.path),
            ["/tmp/custom/sessions", "/tmp/custom/archived_sessions"])
        XCTAssertEqual(LocalActivityReader.defaultRoots(provider: .claude,
            environment: ["CLAUDE_CONFIG_DIR": "/tmp/custom"], homeDirectory: root).map(\.path),
            ["/tmp/custom/projects"])
    }

    func testTruncatedCodexLogUsesFirstCounterAsBaseline() throws {
        try write("truncated.jsonl", [context("a"), tokens(1000, output: 100, second: 2),
                                     tokens(1200, output: 120, second: 4)])
        let report = LocalActivityReader().read(provider: .codex, roots: [root], since: start)
        XCTAssertEqual(report.records.reduce(0) { $0 + $1.total }, 220)
        XCTAssertTrue(report.isPartial)
        XCTAssertEqual(report.skippedCount, 1)
    }

    func testRecentUsageContinuesPastExpiredHistoryAndRetentionCap() throws {
        var lines = [meta("s"), context("a")]
        for index in 1...12 { lines.append(tokens(index * 100, output: index * 10, second: Double(index))) }
        let file = try write("long.jsonl", lines)
        let reader = LocalActivityReader(maxRetainedEvents: 3)
        let since = start.addingTimeInterval(11)
        let initial = reader.read(provider: .codex, roots: [root], since: since)
        XCTAssertEqual(initial.records.reduce(0) { $0 + $1.total }, 220)
        XCTAssertFalse(initial.isPartial)
        let handle = try FileHandle(forWritingTo: file)
        try handle.seekToEnd()
        for index in 13...16 {
            var line = try JSONSerialization.data(withJSONObject: tokens(index * 100, output: index * 10, second: Double(index)))
            line.append(10); try handle.write(contentsOf: line)
        }
        try handle.close()
        let capped = reader.read(provider: .codex, roots: [root], since: since)
        XCTAssertEqual(capped.records.count, 3)
        XCTAssertEqual(capped.records.last?.date, start.addingTimeInterval(16))
        XCTAssertEqual(capped.records.reduce(0) { $0 + $1.total }, 330)
        XCTAssertTrue(capped.isPartial)
        let expanded = reader.read(provider: .codex, roots: [root], since: start.addingTimeInterval(15))
        XCTAssertEqual(expanded.records.reduce(0) { $0 + $1.total }, 220)
    }

    func testUnknownModelAloneAndMalformedUsageArePartial() throws {
        var unknown = claude(output: 10)
        var message = unknown["message"] as! [String: Any]
        message.removeValue(forKey: "model"); unknown["message"] = message
        try write("unknown.jsonl", [unknown])
        let report = LocalActivityReader().read(provider: .claude, roots: [root], since: start)
        XCTAssertEqual(report.unattributedCount, 1)
        XCTAssertTrue(report.isPartial)
        message["usage"] = ["input_tokens": "bad", "output_tokens": 10]
        unknown["message"] = message
        try write("unknown.jsonl", [unknown])
        let malformed = LocalActivityReader().read(provider: .claude, roots: [root], since: start)
        XCTAssertTrue(malformed.records.isEmpty)
        XCTAssertEqual(malformed.skippedCount, 1)
    }

    func testLastOnlyCounterReconcilesWithFollowingCumulativeSnapshot() throws {
        var last = tokens(100, output: 10, second: 2)
        var payload = last["payload"] as! [String: Any]
        var info = payload["info"] as! [String: Any]
        info["last_token_usage"] = info.removeValue(forKey: "total_token_usage")
        payload["info"] = info; last["payload"] = payload
        try write("mixed.jsonl", [meta("s"), context("a"), last, tokens(150, output: 15, second: 3)])
        let report = LocalActivityReader().read(provider: .codex, roots: [root], since: start)
        XCTAssertEqual(report.records.reduce(0) { $0 + $1.total }, 165)
    }

    private func stamp(_ second: Double = 1) -> String {
        ISO8601DateFormatter().string(from: start.addingTimeInterval(second))
    }
    private func claude(output: Int) -> [String: Any] {
        ["type": "assistant", "timestamp": stamp(), "sessionId": "claude-session", "requestId": "request",
         "cwd": "/tmp/sample", "message": ["id": "message", "model": "claude-sonnet-test", "usage": [
            "input_tokens": 100, "cache_creation_input_tokens": 40, "cache_read_input_tokens": 500,
            "output_tokens": output]]]
    }
    private func meta(_ id: String, parent: String? = nil, second: Double = 0) -> [String: Any] {
        var payload: [String: Any] = ["id": id, "cwd": "/tmp/sample", "timestamp": stamp(second)]
        if let parent { payload["forked_from_id"] = parent }
        return ["type": "session_meta", "timestamp": stamp(second), "payload": payload]
    }
    private func context(_ model: String) -> [String: Any] {
        ["type": "turn_context", "timestamp": stamp(), "payload": ["model": model]]
    }
    private func tokens(_ input: Int, output: Int, second: Double) -> [String: Any] {
        ["type": "event_msg", "timestamp": stamp(second), "payload": ["type": "token_count", "info": [
            "model": "stale-event-model", "total_token_usage": ["input_tokens": input,
                "cached_input_tokens": input / 2, "output_tokens": output, "reasoning_output_tokens": output / 2]]]]
    }
    @discardableResult
    private func write(_ name: String, _ lines: [[String: Any]]) throws -> URL {
        let file = root.appendingPathComponent(name)
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        var data = Data()
        for line in lines { data.append(try JSONSerialization.data(withJSONObject: line)); data.append(10) }
        try data.write(to: file)
        return file
    }
}
