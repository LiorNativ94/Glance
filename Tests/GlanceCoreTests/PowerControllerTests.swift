import XCTest
import GlanceCore
@testable import Glance

final class PowerControllerTests: XCTestCase {
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
