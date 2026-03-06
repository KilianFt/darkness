import CoreGraphics
import XCTest
@testable import Darkness

@MainActor
final class DisplayStateControllerTests: XCTestCase {
    func testRefreshSelectsFirstExternalDisplay() {
        let inventory = StubInventory(displays: [
            display(id: 1, isBuiltIn: true),
            display(id: 2, name: "External A"),
            display(id: 3, name: "External B"),
        ])
        let blackout = SpyBlackoutManager()
        let controller = DisplayStateController(inventory: inventory, blackoutManager: blackout)

        let displays = controller.refreshDisplays()

        XCTAssertEqual(displays.map(\.id), [2, 3])
        XCTAssertEqual(controller.selectedDisplayID, 2)
    }

    func testToggleTurnsSelectedDisplayOffThenOn() {
        let inventory = StubInventory(displays: [display(id: 2, name: "External A")])
        let blackout = SpyBlackoutManager()
        let controller = DisplayStateController(inventory: inventory, blackoutManager: blackout)

        _ = controller.refreshDisplays()
        let firstToggle = controller.toggleSelectedDisplay()
        let secondToggle = controller.toggleSelectedDisplay()

        XCTAssertEqual(firstToggle, .turnedOff(display(id: 2, name: "External A")))
        XCTAssertEqual(secondToggle, .turnedOn(display(id: 2, name: "External A")))
        XCTAssertEqual(
            blackout.actions,
            [
                .set(displayID: 2, isBlackout: true),
                .set(displayID: 2, isBlackout: false),
            ]
        )
        XCTAssertNil(controller.activeBlackoutDisplayID)
    }

    func testToggleSwitchesBlackoutToNewSelection() {
        let inventory = StubInventory(displays: [
            display(id: 2, name: "External A"),
            display(id: 3, name: "External B"),
        ])
        let blackout = SpyBlackoutManager()
        let controller = DisplayStateController(inventory: inventory, blackoutManager: blackout)

        _ = controller.refreshDisplays()
        _ = controller.toggleSelectedDisplay()
        _ = controller.select(displayID: 3)
        _ = controller.toggleSelectedDisplay()

        XCTAssertEqual(
            blackout.actions,
            [
                .set(displayID: 2, isBlackout: true),
                .set(displayID: 2, isBlackout: false),
                .set(displayID: 3, isBlackout: true),
            ]
        )
        XCTAssertEqual(controller.activeBlackoutDisplayID, 3)
    }

    func testToggleWhenNoExternalDisplaysReturnsExpectedOutcome() {
        let inventory = StubInventory(displays: [display(id: 1, isBuiltIn: true)])
        let blackout = SpyBlackoutManager()
        let controller = DisplayStateController(inventory: inventory, blackoutManager: blackout)

        let outcome = controller.toggleSelectedDisplay()

        XCTAssertEqual(outcome, .noExternalDisplays)
        XCTAssertEqual(blackout.actions, [])
        XCTAssertNil(controller.selectedDisplayID)
    }

    func testDisconnectingActiveDisplayClearsAllBlackoutWindows() {
        let inventory = StubInventory(displays: [display(id: 2)])
        let blackout = SpyBlackoutManager()
        let controller = DisplayStateController(inventory: inventory, blackoutManager: blackout)

        _ = controller.refreshDisplays()
        _ = controller.toggleSelectedDisplay()
        inventory.displays = []

        _ = controller.refreshDisplays()

        XCTAssertEqual(
            blackout.actions,
            [
                .set(displayID: 2, isBlackout: true),
                .clearAll,
            ]
        )
        XCTAssertNil(controller.activeBlackoutDisplayID)
    }

    func testCycleSelectionWrapsAround() {
        let inventory = StubInventory(displays: [
            display(id: 2, name: "External A"),
            display(id: 3, name: "External B"),
        ])
        let blackout = SpyBlackoutManager()
        let controller = DisplayStateController(inventory: inventory, blackoutManager: blackout)

        _ = controller.refreshDisplays()
        let next = controller.cycleSelection()
        let wrapped = controller.cycleSelection()

        XCTAssertEqual(next, display(id: 3, name: "External B"))
        XCTAssertEqual(wrapped, display(id: 2, name: "External A"))
        XCTAssertEqual(controller.selectedDisplayID, 2)
    }

    func testDeactivateBlackoutIfNeededTurnsOffActiveDisplay() {
        let inventory = StubInventory(displays: [display(id: 2, name: "External A")])
        let blackout = SpyBlackoutManager()
        let controller = DisplayStateController(inventory: inventory, blackoutManager: blackout)

        _ = controller.refreshDisplays()
        _ = controller.toggleSelectedDisplay()
        controller.deactivateBlackoutIfNeeded()

        XCTAssertEqual(
            blackout.actions,
            [
                .set(displayID: 2, isBlackout: true),
                .set(displayID: 2, isBlackout: false),
            ]
        )
        XCTAssertNil(controller.activeBlackoutDisplayID)
    }
}

@MainActor
private final class StubInventory: DisplayInventory {
    var displays: [DisplayDescriptor]

    init(displays: [DisplayDescriptor]) {
        self.displays = displays
    }

    func listDisplays() -> [DisplayDescriptor] {
        displays
    }
}

@MainActor
private final class SpyBlackoutManager: BlackoutWindowManaging {
    enum Action: Equatable {
        case set(displayID: CGDirectDisplayID, isBlackout: Bool)
        case clearAll
    }

    private(set) var actions: [Action] = []

    func setBlackout(_ isBlackout: Bool, for display: DisplayDescriptor) {
        actions.append(.set(displayID: display.id, isBlackout: isBlackout))
    }

    func clearAll() {
        actions.append(.clearAll)
    }
}

private func display(
    id: CGDirectDisplayID,
    name: String = "External",
    frame: CGRect = CGRect(x: 0, y: 0, width: 1920, height: 1080),
    visibleFrame: CGRect? = nil,
    isBuiltIn: Bool = false
) -> DisplayDescriptor {
    DisplayDescriptor(
        id: id,
        name: name,
        frame: frame,
        visibleFrame: visibleFrame ?? frame,
        isBuiltIn: isBuiltIn
    )
}
