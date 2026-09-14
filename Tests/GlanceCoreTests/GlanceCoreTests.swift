import XCTest
@testable import GlanceCore

final class GlanceCoreTests: XCTestCase {
    func testCPUUsesSampleDeltaRatherThanLifetimeAverage() {
        let before = CPUTicks(busy: 900, idle: 100)
        let after = CPUTicks(busy: 920, idle: 180)
        XCTAssertEqual(after.usage(since: before)!, 0.2, accuracy: 0.0001)
        XCTAssertNil(before.usage(since: before))
        XCTAssertNil(before.usage(since: after))
    }
    func testDisconnectedDriveDisappearsWithoutLosingItsSelection() {
        let saved = ["memory", "volume:ssd", "cpu", "cpu"]
        XCTAssertEqual(MetricSelection.visible(selected: saved, available: ["cpu", "memory"]), ["memory", "cpu"])
        XCTAssertEqual(MetricSelection.visible(selected: saved, available: ["cpu", "memory", "volume:ssd"]), ["memory", "volume:ssd", "cpu"])
    }
    func testEmptyOrUnavailableSelectionNeedsSingleFallbackIcon() {
        XCTAssertTrue(MetricSelection.visible(selected: [], available: ["cpu", "memory"]).isEmpty)
        XCTAssertTrue(MetricSelection.visible(selected: ["volume:ssd"], available: ["cpu"]).isEmpty)
    }
    func testStorageReflectsSharedCapacityAndClampsInvalidValues() {
        let disk = StorageVolume(id: "d", name: "SSD", path: "/Volumes/SSD", total: 1000, available: 900, isInternal: false)
        XCTAssertEqual(disk.used, 100)
        XCTAssertEqual(disk.fraction, 0.1, accuracy: 0.0001)
        let invalid = StorageVolume(id: "x", name: "X", path: "/", total: 1000, available: 1200, isInternal: true)
        XCTAssertEqual(invalid.used, 0)
    }
    func testMountedDiskImagesAreNotListedAsDrives() {
        // The startup disk is a sealed read-only volume and must survive the filter.
        XCTAssertTrue(StorageFilter.isUserStorage(path: "/", isLocal: true, isReadOnly: true))
        // An installer DMG left mounted is read-only and reports space the user can never change.
        XCTAssertFalse(StorageFilter.isUserStorage(path: "/Volumes/Acta", isLocal: true, isReadOnly: true))
        // A writable external drive is still real storage.
        XCTAssertTrue(StorageFilter.isUserStorage(path: "/Volumes/SSD", isLocal: true, isReadOnly: false))
        // Network mounts and hidden support volumes stay excluded.
        XCTAssertFalse(StorageFilter.isUserStorage(path: "/Volumes/Share", isLocal: false, isReadOnly: false))
        XCTAssertFalse(StorageFilter.isUserStorage(path: "/System/Volumes/VM", isLocal: true, isReadOnly: false))
    }
    func testSleepLeaseEndsOnCrashHangDeadlineAndLowBattery() {
        XCTAssertTrue(LeasePolicy.shouldEnd(now: 100, lastHeartbeat: 100, parentAlive: false, deadline: nil, battery: nil))
        XCTAssertTrue(LeasePolicy.shouldEnd(now: 100, lastHeartbeat: 84, parentAlive: true, deadline: nil, battery: nil))
        XCTAssertTrue(LeasePolicy.shouldEnd(now: 100, lastHeartbeat: 99, parentAlive: true, deadline: 100, battery: nil))
        let low = BatteryReading(fraction: 0.1, charging: false, onAC: false)
        XCTAssertTrue(LeasePolicy.shouldEnd(now: 100, lastHeartbeat: 99, parentAlive: true, deadline: nil, battery: low))
        let plugged = BatteryReading(fraction: 0.1, charging: true, onAC: true)
        XCTAssertFalse(LeasePolicy.shouldEnd(now: 100, lastHeartbeat: 99, parentAlive: true, deadline: 200, battery: plugged))
    }
    func testUnknownMetricsNeverPretendToBeZero() {
        XCTAssertEqual(ReadingFormat.percent(nil), "—")
        XCTAssertNil(SystemSnapshot().memoryFraction)
        XCTAssertEqual(ReadingFormat.percent(0.678), "68%")
    }
}
