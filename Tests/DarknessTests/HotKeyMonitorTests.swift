import Carbon.HIToolbox
import XCTest
@testable import Darkness

final class HotKeyMonitorTests: XCTestCase {
    func testShouldRetryRegistrationStatusWhenHotKeyAlreadyExists() {
        XCTAssertTrue(
            HotKeyMonitor.shouldRetryRegistrationStatus(OSStatus(eventHotKeyExistsErr))
        )
    }

    func testShouldRetryRegistrationStatusRejectsNoErr() {
        XCTAssertFalse(
            HotKeyMonitor.shouldRetryRegistrationStatus(noErr)
        )
    }

    func testShouldRetryRegistrationStatusRejectsParamErr() {
        XCTAssertFalse(
            HotKeyMonitor.shouldRetryRegistrationStatus(OSStatus(paramErr))
        )
    }
}
