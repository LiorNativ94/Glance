import AppKit
import IOKit.pwr_mgt
import GlanceCore

final class PowerController: ObservableObject {
    @Published private(set) var active = false
    @Published private(set) var lidActive = false
    @Published private(set) var authorizing = false
    @Published var duration = 60
    @Published private(set) var displayOn = false
    @Published private(set) var deadline: Date?
    @Published private(set) var now = Date()
    @Published var message: String?
    private var systemAssertion: IOPMAssertionID = 0
    private var displayAssertion: IOPMAssertionID = 0
    private var timer: Timer?
    private var sessionDirectory: URL?
    @Published private(set) var lidStopping = false

    init() {
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in self?.tick() }
        timer?.tolerance = 0.15
    }
    deinit {
        timer?.invalidate()
        if let directory = sessionDirectory { try? FileManager.default.removeItem(at: directory.appendingPathComponent("heartbeat")) }
        if displayAssertion != 0 { IOPMAssertionRelease(displayAssertion) }
        if systemAssertion != 0 { IOPMAssertionRelease(systemAssertion) }
    }
    var remaining: String {
        guard active else { return "Let your Mac sleep normally" }
        guard let deadline else { return "Until you turn it off" }
        let seconds = max(0, Int(ceil(deadline.timeIntervalSince(now))))
        return seconds < 60 ? "\(seconds) sec remaining" : "\(Int(ceil(Double(seconds) / 60))) min remaining"
    }
    func setActive(_ enabled: Bool) {
        if !enabled { stop(); return }
        guard !active else { return }
        var id: IOPMAssertionID = 0
        let result = IOPMAssertionCreateWithName(kIOPMAssertionTypePreventUserIdleSystemSleep as CFString,
                                                IOPMAssertionLevel(kIOPMAssertionLevelOn),
                                                "Glance — keep awake session" as CFString, &id)
        guard result == kIOReturnSuccess else { message = "macOS couldn’t start keep-awake (\(result))."; return }
        systemAssertion = id
        active = true
        resetDeadline()
    }
    func selectDuration(_ minutes: Int) {
        duration = minutes
        if active { resetDeadline() }
    }
    func extendSession(by minutes: Int) {
        guard active, let deadline, deadline > Date(), minutes > 0 else { return }
        self.deadline = deadline.addingTimeInterval(Double(minutes) * 60)
        now = .now
        updateHeartbeat()
    }
    private func resetDeadline() {
        now = .now; deadline = duration == 0 ? nil : now.addingTimeInterval(Double(duration) * 60)
        updateHeartbeat()
    }
    func setDisplay(_ enabled: Bool) {
        if displayAssertion != 0 { IOPMAssertionRelease(displayAssertion); displayAssertion = 0 }
        displayOn = false
        guard enabled, active else { return }
        var id: IOPMAssertionID = 0
        let result = IOPMAssertionCreateWithName(kIOPMAssertionTypePreventUserIdleDisplaySleep as CFString,
                                                IOPMAssertionLevel(kIOPMAssertionLevelOn),
                                                "Glance — keep display on" as CFString, &id)
        if result == kIOReturnSuccess { displayAssertion = id; displayOn = true }
        else { message = "macOS couldn’t keep the display on (\(result))." }
    }
    func stop() {
        endLidSession()
        setDisplay(false)
        if systemAssertion != 0 { IOPMAssertionRelease(systemAssertion); systemAssertion = 0 }
        active = false; deadline = nil
    }
    func checkBattery(_ battery: BatteryReading?) {
        if active, let battery, !battery.onAC, battery.fraction <= 0.1 {
            stop(); message = "Keep-awake stopped because the battery reached 10%."
        }
    }
    private func tick() {
        now = .now
        if active, let deadline, now >= deadline { stop() }
        updateHeartbeat()
        if let directory = sessionDirectory {
            let status = (try? String(contentsOf: directory.appendingPathComponent("status"), encoding: .utf8)) ?? ""
            if status.hasPrefix("active") { lidActive = true; authorizing = false }
            else if status.hasPrefix("error:") || status.hasPrefix("ended") {
                if status.hasPrefix("error:") { message = String(status.dropFirst(6)) }
                sessionDirectory = nil; lidActive = false; authorizing = false; lidStopping = false
                try? FileManager.default.removeItem(at: directory)
            }
        }
    }
    private func updateHeartbeat() {
        guard let directory = sessionDirectory, !lidStopping else { return }
        let record = "\(Date().timeIntervalSince1970)\n\(deadline?.timeIntervalSince1970 ?? 0)\n"
        try? record.write(to: directory.appendingPathComponent("heartbeat"), atomically: true, encoding: .utf8)
    }
    func endLidSession() {
        if let directory = sessionDirectory {
            lidStopping = true
            try? FileManager.default.removeItem(at: directory.appendingPathComponent("heartbeat"))
        }
        // Helper acknowledges restoration through its status file before the UI claims it is off.
        if sessionDirectory == nil { lidActive = false }
    }
    func startLidSession() {
        guard !authorizing, !lidActive, !lidStopping else { return }
        guard SystemReader.systemSleepDisabled() == false else {
            message = "Sleep is already disabled by another tool, or its state could not be read. Glance won’t change it."
            return
        }
        setActive(true)
        guard active else { return }
        guard let executable = Bundle.main.executableURL?.deletingLastPathComponent().appendingPathComponent("GlancePowerHelper"),
              FileManager.default.isExecutableFile(atPath: executable.path) else {
            message = "The sleep helper is missing. Rebuild Glance using build.sh."; return
        }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("Glance-\(UUID().uuidString)")
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false,
                                                    attributes: [.posixPermissions: 0o700])
            FileManager.default.createFile(atPath: directory.appendingPathComponent("status").path, contents: Data(),
                                           attributes: [.posixPermissions: 0o600])
        } catch { message = error.localizedDescription; return }
        sessionDirectory = directory; authorizing = true; updateHeartbeat()
        let command = [executable.path, "--session", directory.path, "--owner", String(getpid())].map(Self.shellQuote).joined(separator: " ")
        // This authorization lasts for this process only: no sudoers rules or installed root service.
        let script = "with timeout of 31536000 seconds\ndo shell script \"\(Self.appleScriptEscape(command))\" with administrator privileges\nend timeout"
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            var error: NSDictionary?
            _ = NSAppleScript(source: script)?.executeAndReturnError(&error)
            let errorText = error?[NSAppleScript.errorMessage] as? String
            DispatchQueue.main.async {
                guard let self, self.sessionDirectory == directory else { return }
                self.authorizing = false
                self.lidActive = false
                self.lidStopping = false
                let status = (try? String(contentsOf: directory.appendingPathComponent("status"), encoding: .utf8)) ?? ""
                if status.hasPrefix("error:") { self.message = String(status.dropFirst(6)) }
                else if let errorText { self.message = errorText }
                self.sessionDirectory = nil
                try? FileManager.default.removeItem(at: directory)
            }
        }
    }
    private static func shellQuote(_ text: String) -> String { "'" + text.replacingOccurrences(of: "'", with: "'\\''") + "'" }
    private static func appleScriptEscape(_ text: String) -> String {
        text.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
    }
}
