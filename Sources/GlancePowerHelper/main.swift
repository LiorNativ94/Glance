import Foundation
import Darwin
import GlanceCore

// A session-scoped privileged worker. No installed daemon, network access or shell input.
// It restores the kernel sleep flag independently if the UI quits, crashes or loses its heartbeat.
let args = CommandLine.arguments
guard geteuid() == 0, args.count == 5, args[1] == "--session", args[3] == "--owner",
      let ownerPID = Int32(args[4]), ownerPID > 1 else {
    fputs("GlancePowerHelper must be started by Glance with administrator authorization.\n", stderr)
    exit(64)
}
let session = args[2]
guard URL(fileURLWithPath: session).lastPathComponent.hasPrefix("Glance-") else { exit(64) }
var directoryInfo = stat()
guard lstat(session, &directoryInfo) == 0, (directoryInfo.st_mode & S_IFMT) == S_IFDIR,
      directoryInfo.st_uid != 0, directoryInfo.st_mode & 0o077 == 0 else { exit(64) }
let dirFD = open(session, O_RDONLY | O_DIRECTORY | O_NOFOLLOW)
guard dirFD >= 0 else { exit(64) }
defer { close(dirFD) }
let ownerUID = directoryInfo.st_uid

func writeStatus(_ text: String) {
    let fd = openat(dirFD, "status", O_WRONLY | O_NOFOLLOW)
    guard fd >= 0 else { return }
    defer { close(fd) }
    var info = stat()
    guard fstat(fd, &info) == 0, info.st_uid == ownerUID,
          (info.st_mode & S_IFMT) == S_IFREG, info.st_nlink == 1 else { return }
    guard ftruncate(fd, 0) == 0 else { return }
    _ = text.withCString { write(fd, $0, strlen($0)) }
}
func heartbeat() -> (TimeInterval, TimeInterval?)? {
    let fd = openat(dirFD, "heartbeat", O_RDONLY | O_NOFOLLOW)
    guard fd >= 0 else { return nil }
    defer { close(fd) }
    var info = stat()
    guard fstat(fd, &info) == 0, info.st_uid == ownerUID,
          (info.st_mode & S_IFMT) == S_IFREG, info.st_size < 256 else { return nil }
    var bytes = [UInt8](repeating: 0, count: 256)
    let length = read(fd, &bytes, 255)
    guard length > 0 else { return nil }
    let fields = String(decoding: bytes.prefix(length), as: UTF8.self).split(separator: "\n")
    guard fields.count == 2, let stamp = Double(fields[0]), let deadline = Double(fields[1]),
          stamp.isFinite, deadline.isFinite else { return nil }
    return (stamp, deadline > 0 ? deadline : nil)
}
func setSleepDisabled(_ disabled: Bool) -> Bool {
    let task = Process()
    task.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
    task.arguments = ["-a", "disablesleep", disabled ? "1" : "0"]
    task.standardOutput = FileHandle.nullDevice
    task.standardError = FileHandle.nullDevice
    do { try task.run(); task.waitUntilExit() } catch { return false }
    return task.terminationStatus == 0 && SystemReader.systemSleepDisabled() == disabled
}

let lockFD = open("/var/run/com.liornativ.Glance.sleep.lock", O_CREAT | O_RDWR | O_NOFOLLOW, 0o600)
guard lockFD >= 0 else { writeStatus("error:Could not lock the sleep session."); exit(1) }
defer { close(lockFD) }
var lockInfo = stat()
guard fstat(lockFD, &lockInfo) == 0, lockInfo.st_uid == 0,
      (lockInfo.st_mode & S_IFMT) == S_IFREG,
      flock(lockFD, LOCK_EX | LOCK_NB) == 0 else {
    writeStatus("error:Another Glance sleep session is already running."); exit(1)
}
guard SystemReader.systemSleepDisabled() == false else {
    writeStatus("error:Another tool already disabled sleep, or the sleep state is unavailable."); exit(1)
}
guard let initial = heartbeat(),
      !LeasePolicy.shouldEnd(now: Date().timeIntervalSince1970, lastHeartbeat: initial.0,
                            parentAlive: kill(ownerPID, 0) == 0, deadline: initial.1, battery: SystemReader.battery()) else {
    writeStatus("ended"); exit(0)
}
// Install signal handling before changing state so SIGTERM/SIGINT also take the cleanup path.
signal(SIGTERM, SIG_IGN)
signal(SIGINT, SIG_IGN)
let signalQueue = DispatchQueue(label: "Glance.helper.signals")
let stopLock = NSLock()
var interrupted = false
let sources = [SIGTERM, SIGINT].map { sig -> DispatchSourceSignal in
    let source = DispatchSource.makeSignalSource(signal: sig, queue: signalQueue)
    source.setEventHandler { stopLock.lock(); interrupted = true; stopLock.unlock() }
    source.resume()
    return source
}
var changed = false
func restore() -> Bool {
    guard changed else { return true }
    for _ in 0..<3 {
        if setSleepDisabled(false) { changed = false; return true }
        Thread.sleep(forTimeInterval: 1)
    }
    return false
}
defer { _ = restore(); sources.forEach { $0.cancel() } }
// Even if verification fails after a successful pmset write, attempt restoration.
changed = true
guard setSleepDisabled(true) else {
    let restored = restore()
    writeStatus(restored ? "error:macOS did not accept the closed-lid sleep override." : "error:Could not restore sleep. Run sudo pmset -a disablesleep 0 in Terminal.")
    exit(1)
}
writeStatus("active")
while true {
    stopLock.lock(); let stop = interrupted; stopLock.unlock()
    guard !stop, let beat = heartbeat() else { break }
    if LeasePolicy.shouldEnd(now: Date().timeIntervalSince1970, lastHeartbeat: beat.0,
                             parentAlive: kill(ownerPID, 0) == 0, deadline: beat.1, battery: SystemReader.battery()) { break }
    // Reapply after power-source transitions if macOS reset the kernel flag.
    if SystemReader.systemSleepDisabled() == false, !setSleepDisabled(true) { break }
    Thread.sleep(forTimeInterval: 1)
}
let restored = restore()
writeStatus(restored ? "ended" : "error:Could not restore sleep. Run sudo pmset -a disablesleep 0 in Terminal.")
if !restored { exit(1) }
