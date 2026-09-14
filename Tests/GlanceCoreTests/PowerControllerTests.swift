import XCTest
import GlanceCore
@testable import Glance

final class PowerControllerTests: XCTestCase {
    func testExtensionsAddToTheDeadlineWithoutChangingUntimedOrStoppedSessions() throws {
        let power = PowerController()
        defer { power.stop() }
        power.extendSession(by: 15)
        XCTAssertFalse(power.active)
        XCTAssertNil(power.deadline)
        power.setActive(true)
        let initial = try XCTUnwrap(power.deadline)
        power.extendSession(by: 15)
        XCTAssertEqual(try XCTUnwrap(power.deadline).timeIntervalSince(initial), 900, accuracy: 0.01)
        power.extendSession(by: 30)
        XCTAssertEqual(try XCTUnwrap(power.deadline).timeIntervalSince(initial), 2700, accuracy: 0.01)
        power.extendSession(by: -15)
        XCTAssertEqual(try XCTUnwrap(power.deadline).timeIntervalSince(initial), 2700, accuracy: 0.01)
        power.selectDuration(0)
        power.extendSession(by: 30)
        XCTAssertTrue(power.active)
        XCTAssertNil(power.deadline)
        power.stop()
        power.extendSession(by: 30)
        XCTAssertFalse(power.active)
        XCTAssertNil(power.deadline)
    }
    func testDisplayCannotBeKeptOnOutsideASession() {
        let power = PowerController()
        power.setDisplay(true)
        XCTAssertFalse(power.active)
        XCTAssertFalse(power.displayOn)
    }
    func testSessionStartStopAndDurationChanges() throws {
        let power = PowerController()
        defer { power.stop() }
        power.setActive(true)
        XCTAssertTrue(power.active, power.message ?? "Power assertion failed")
        XCTAssertNotNil(power.deadline)
        power.selectDuration(0)
        XCTAssertNil(power.deadline)
        power.selectDuration(30)
        XCTAssertEqual(power.deadline!.timeIntervalSinceNow, 1800, accuracy: 2)
        power.setDisplay(true)
        XCTAssertTrue(power.displayOn, power.message ?? "Display assertion failed")
        power.stop()
        XCTAssertFalse(power.active)
        XCTAssertFalse(power.displayOn)
        XCTAssertNil(power.deadline)
    }
    func testLowBatteryEndsSessionButChargingDoesNot() {
        let power = PowerController()
        defer { power.stop() }
        power.setActive(true)
        power.checkBattery(BatteryReading(fraction: 0.08, charging: true, onAC: true))
        XCTAssertTrue(power.active)
        power.checkBattery(BatteryReading(fraction: 0.1, charging: false, onAC: false))
        XCTAssertFalse(power.active)
        XCTAssertNotNil(power.message)
    }
}
