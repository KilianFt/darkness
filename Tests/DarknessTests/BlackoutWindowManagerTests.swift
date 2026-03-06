import CoreGraphics
import XCTest
@testable import Darkness

@MainActor
final class BlackoutWindowManagerTests: XCTestCase {
    func testSetBlackoutTrueCreatesAndShowsWindow() {
        let factory = SpyFactory()
        let manager = BlackoutWindowManager(factory: factory)
        let display = makeDisplay(id: 42, frame: CGRect(x: 10, y: 20, width: 1440, height: 900))

        manager.setBlackout(true, for: display)

        XCTAssertEqual(factory.createdWindows.count, 1)
        XCTAssertEqual(factory.createdWindows[0].frames, [display.frame])
        XCTAssertEqual(factory.createdWindows[0].showCount, 1)
        XCTAssertEqual(factory.createdWindows[0].hideCount, 0)
    }

    func testToggleOffThenOnReusesExistingWindow() {
        let factory = SpyFactory()
        let manager = BlackoutWindowManager(factory: factory)
        let display = makeDisplay(id: 42)

        manager.setBlackout(true, for: display)
        manager.setBlackout(false, for: display)
        manager.setBlackout(true, for: display)

        XCTAssertEqual(factory.createdWindows.count, 1)
        XCTAssertEqual(factory.createdWindows[0].showCount, 2)
        XCTAssertEqual(factory.createdWindows[0].hideCount, 1)
    }

    func testClearAllHidesEveryManagedWindow() {
        let factory = SpyFactory()
        let manager = BlackoutWindowManager(factory: factory)
        let displayA = makeDisplay(id: 1, frame: CGRect(x: 0, y: 0, width: 1920, height: 1080))
        let displayB = makeDisplay(id: 2, frame: CGRect(x: 1920, y: 0, width: 2560, height: 1440))

        manager.setBlackout(true, for: displayA)
        manager.setBlackout(true, for: displayB)
        manager.clearAll()

        XCTAssertEqual(factory.createdWindows.count, 2)
        XCTAssertEqual(factory.createdWindows[0].hideCount, 1)
        XCTAssertEqual(factory.createdWindows[1].hideCount, 1)
    }
}

@MainActor
private final class SpyFactory: BlackoutWindowFactory {
    private(set) var createdWindows: [SpyWindow] = []

    func makeWindow(for display: DisplayDescriptor) -> BlackoutWindow {
        let window = SpyWindow()
        createdWindows.append(window)
        return window
    }
}

@MainActor
private final class SpyWindow: BlackoutWindow {
    private(set) var frames: [CGRect] = []
    private(set) var showCount = 0
    private(set) var hideCount = 0

    func setFrame(_ frame: CGRect) {
        frames.append(frame)
    }

    func show() {
        showCount += 1
    }

    func hide() {
        hideCount += 1
    }
}

private func makeDisplay(
    id: CGDirectDisplayID,
    frame: CGRect = CGRect(x: 0, y: 0, width: 1920, height: 1080),
    visibleFrame: CGRect? = nil
) -> DisplayDescriptor {
    DisplayDescriptor(
        id: id,
        name: "External",
        frame: frame,
        visibleFrame: visibleFrame ?? frame,
        isBuiltIn: false
    )
}
