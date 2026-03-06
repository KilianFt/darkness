import CoreGraphics
import XCTest
@testable import Darkness

@MainActor
final class FocusModeControllerTests: XCTestCase {
    func testToggleActivatesAndPassesFocusedFrameToOverlay() {
        let inventory = StubDisplayInventory(displays: [display(id: 10), display(id: 11)])
        let focusedFrame = CGRect(x: 120, y: 140, width: 900, height: 600)
        let provider = StubFocusedWindowProvider(frame: focusedFrame)
        let overlay = SpyFocusOverlayManager()
        let controller = FocusModeController(
            displayInventory: inventory,
            focusedWindowProvider: provider,
            overlayManager: overlay
        )

        let outcome = controller.toggle()

        XCTAssertEqual(outcome, .activated(focusedFrame))
        XCTAssertEqual(overlay.actions, [.show(frame: focusedFrame, displayIDs: [10, 11])])
        XCTAssertTrue(controller.isActive)
    }

    func testToggleTwiceDeactivatesFocusMode() {
        let inventory = StubDisplayInventory(displays: [display(id: 10)])
        let provider = StubFocusedWindowProvider(frame: CGRect(x: 10, y: 20, width: 800, height: 500))
        let overlay = SpyFocusOverlayManager()
        let controller = FocusModeController(
            displayInventory: inventory,
            focusedWindowProvider: provider,
            overlayManager: overlay
        )

        _ = controller.toggle()
        let secondOutcome = controller.toggle()

        XCTAssertEqual(secondOutcome, .deactivated)
        XCTAssertEqual(
            overlay.actions,
            [
                .show(frame: CGRect(x: 10, y: 20, width: 800, height: 500), displayIDs: [10]),
                .hide,
            ]
        )
        XCTAssertFalse(controller.isActive)
    }

    func testToggleWithoutFocusedWindowDoesNotActivate() {
        let inventory = StubDisplayInventory(displays: [display(id: 10)])
        let provider = StubFocusedWindowProvider(frame: nil)
        let overlay = SpyFocusOverlayManager()
        let controller = FocusModeController(
            displayInventory: inventory,
            focusedWindowProvider: provider,
            overlayManager: overlay
        )

        let outcome = controller.toggle()

        XCTAssertEqual(outcome, .noFocusedWindow)
        XCTAssertEqual(overlay.actions, [])
        XCTAssertFalse(controller.isActive)
    }

    func testToggleAlignsFocusedFrameToPixelGrid() {
        let inventory = StubDisplayInventory(displays: [display(id: 10)])
        let provider = StubFocusedWindowProvider(frame: CGRect(x: 10.2, y: 20.3, width: 800.1, height: 500.1))
        let overlay = SpyFocusOverlayManager()
        let controller = FocusModeController(
            displayInventory: inventory,
            focusedWindowProvider: provider,
            overlayManager: overlay
        )

        let outcome = controller.toggle()

        XCTAssertEqual(outcome, .activated(CGRect(x: 10, y: 20, width: 801, height: 501)))
        XCTAssertEqual(
            overlay.actions,
            [.show(frame: CGRect(x: 10, y: 20, width: 801, height: 501), displayIDs: [10])]
        )
    }

    func testAccessibilityFrameConversionFromTopLeftToBottomLeft() {
        let provider = AccessibilityFocusedWindowProvider()
        let converted = provider.convertFromTopLeftToBottomLeft(
            CGRect(x: 100, y: 20, width: 300, height: 200),
            virtualDesktopMaxY: 1080
        )

        XCTAssertEqual(converted, CGRect(x: 100, y: 860, width: 300, height: 200))
    }

    func testFallbackFocusedWindowFrameSelectsFirstFrontmostLayerZeroWindow() {
        let provider = AccessibilityFocusedWindowProvider()
        let info: [[String: Any]] = [
            windowInfo(pid: 100, layer: 0, frame: CGRect(x: 10, y: 20, width: 200, height: 100)),
            windowInfo(pid: 100, layer: 0, frame: CGRect(x: 30, y: 40, width: 600, height: 400)),
            windowInfo(pid: 200, layer: 0, frame: CGRect(x: 0, y: 0, width: 900, height: 700)),
        ]

        let frame = provider.fallbackFocusedWindowFrame(
            from: info,
            frontmostPID: 100,
            virtualDesktopMaxY: 1200
        )

        XCTAssertEqual(frame, CGRect(x: 10, y: 1080, width: 200, height: 100))
    }

    func testFallbackFocusedWindowFrameIgnoresNonZeroLayerWindows() {
        let provider = AccessibilityFocusedWindowProvider()
        let info: [[String: Any]] = [
            windowInfo(pid: 100, layer: 3, frame: CGRect(x: 10, y: 20, width: 400, height: 300)),
            windowInfo(pid: 100, layer: 0, frame: CGRect(x: 50, y: 60, width: 150, height: 120)),
        ]

        let frame = provider.fallbackFocusedWindowFrame(
            from: info,
            frontmostPID: 100,
            virtualDesktopMaxY: 1200
        )

        XCTAssertEqual(frame, CGRect(x: 50, y: 1020, width: 150, height: 120))
    }

    func testFallbackFocusedWindowFrameReturnsNilWithoutValidCandidate() {
        let provider = AccessibilityFocusedWindowProvider()
        let info: [[String: Any]] = [
            windowInfo(pid: 100, layer: 5, frame: CGRect(x: 0, y: 0, width: 300, height: 200)),
            windowInfo(pid: 200, layer: 0, frame: CGRect(x: 20, y: 20, width: 300, height: 200)),
        ]

        let frame = provider.fallbackFocusedWindowFrame(
            from: info,
            frontmostPID: 100,
            virtualDesktopMaxY: 1200
        )

        XCTAssertNil(frame)
    }

    func testFocusedWindowFrameUsesFallbackWhenFocusedElementMissing() {
        let provider = AccessibilityFocusedWindowProvider()
        let expected = CGRect(x: 1, y: 2, width: 3, height: 4)

        let frame = provider.focusedWindowFrame(
            for: nil,
            fallback: { expected }
        )

        XCTAssertEqual(frame, expected)
    }

    func testFocusedWindowFrameUsesFallbackWhenFocusedElementHasNoGeometry() {
        let provider = AccessibilityFocusedWindowProvider()
        let expected = CGRect(x: 11, y: 22, width: 333, height: 444)

        let frame = provider.focusedWindowFrame(
            for: AXUIElementCreateSystemWide(),
            fallback: { expected }
        )

        XCTAssertEqual(frame, expected)
    }

    func testDeactivateIfNeededOnlyHidesWhenActive() {
        let inventory = StubDisplayInventory(displays: [display(id: 10)])
        let provider = StubFocusedWindowProvider(frame: CGRect(x: 1, y: 1, width: 640, height: 480))
        let overlay = SpyFocusOverlayManager()
        let controller = FocusModeController(
            displayInventory: inventory,
            focusedWindowProvider: provider,
            overlayManager: overlay
        )

        controller.deactivateIfNeeded()
        _ = controller.toggle()
        controller.deactivateIfNeeded()

        XCTAssertEqual(
            overlay.actions,
            [
                .show(frame: CGRect(x: 1, y: 1, width: 640, height: 480), displayIDs: [10]),
                .hide,
            ]
        )
        XCTAssertFalse(controller.isActive)
    }

    func testFocusOverlayManagerDefaultsToFullyOpaqueBlack() {
        let manager = FocusOverlayManager()
        XCTAssertEqual(manager.overlayOpacity, 1.0, accuracy: 0.0001)
    }

    func testFocusOverlayManagerDefaultsToZeroBottomCompensation() {
        let manager = FocusOverlayManager()
        XCTAssertEqual(manager.bottomCompensation, 0.0, accuracy: 0.0001)
    }

    func testFocusOverlayManagerDefaultsToSystemWindowCornerRadius() {
        let manager = FocusOverlayManager()
        XCTAssertEqual(manager.focusedWindowCornerRadius, 12.0, accuracy: 0.0001)
    }

    func testCompensatedFocusedFrameExtendsDownward() {
        let manager = FocusOverlayManager(bottomCompensation: 28)
        let frame = CGRect(x: 100, y: 300, width: 1200, height: 700)

        let compensated = manager.compensatedFocusedFrame(frame)

        XCTAssertEqual(compensated, CGRect(x: 100, y: 272, width: 1200, height: 728))
    }

    func testFocusedCutoutCornerRadiusIsClampedToFrameSize() {
        let manager = FocusOverlayManager(focusedWindowCornerRadius: 18)
        let cornerRadius = manager.focusedCutoutCornerRadius(
            for: CGRect(x: 0, y: 0, width: 20, height: 14)
        )

        XCTAssertEqual(cornerRadius, 7, accuracy: 0.0001)
    }

    func testFocusedCutoutCornerRadiusNeverGoesNegative() {
        let manager = FocusOverlayManager(focusedWindowCornerRadius: -5)
        let cornerRadius = manager.focusedCutoutCornerRadius(
            for: CGRect(x: 0, y: 0, width: 200, height: 100)
        )

        XCTAssertEqual(manager.focusedWindowCornerRadius, 0, accuracy: 0.0001)
        XCTAssertEqual(cornerRadius, 0, accuracy: 0.0001)
    }

    func testTopLeftMenuBarRectKeepsLeftHalfOnly() {
        let manager = FocusOverlayManager(topBarVisibleFraction: 0.5)
        let displayFrame = CGRect(x: 0, y: 0, width: 2560, height: 1440)
        let display = display(
            id: 10,
            frame: displayFrame,
            visibleFrame: CGRect(x: 0, y: 0, width: 2560, height: 1416)
        )

        let menuRect = manager.topLeftMenuBarRect(for: display)

        XCTAssertEqual(menuRect, CGRect(x: 0, y: 1416, width: 1280, height: 24))
    }

    func testDefaultTopBarVisibleFractionRemovesTopBarCutout() {
        let manager = FocusOverlayManager()
        let display = display(
            id: 10,
            frame: CGRect(x: 0, y: 0, width: 2560, height: 1440),
            visibleFrame: CGRect(x: 0, y: 0, width: 2560, height: 1416)
        )

        XCTAssertNil(manager.topLeftMenuBarRect(for: display))
    }

    func testContentFrameWithoutTopBarRemovesOnlyTopInset() {
        let manager = FocusOverlayManager()
        let display = display(
            id: 10,
            frame: CGRect(x: 0, y: 0, width: 2560, height: 1440),
            visibleFrame: CGRect(x: 0, y: 50, width: 2560, height: 1366)
        )

        let contentFrame = manager.contentFrameWithoutTopBar(for: display)

        XCTAssertEqual(contentFrame, CGRect(x: 0, y: 0, width: 2560, height: 1416))
    }
}

@MainActor
private final class StubFocusedWindowProvider: FocusedWindowProviding {
    var frame: CGRect?

    init(frame: CGRect?) {
        self.frame = frame
    }

    func focusedWindowFrame() -> CGRect? {
        frame
    }
}

@MainActor
private final class StubDisplayInventory: DisplayInventory {
    let displays: [DisplayDescriptor]

    init(displays: [DisplayDescriptor]) {
        self.displays = displays
    }

    func listDisplays() -> [DisplayDescriptor] {
        displays
    }
}

@MainActor
private final class SpyFocusOverlayManager: FocusOverlayManaging {
    enum Action: Equatable {
        case show(frame: CGRect, displayIDs: [CGDirectDisplayID])
        case hide
    }

    private(set) var actions: [Action] = []

    func show(visibleFrame: CGRect, on displays: [DisplayDescriptor]) {
        actions.append(.show(frame: visibleFrame, displayIDs: displays.map(\.id)))
    }

    func hide() {
        actions.append(.hide)
    }
}

private func display(
    id: CGDirectDisplayID,
    name: String = "Display",
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

private func windowInfo(pid: pid_t, layer: Int, frame: CGRect) -> [String: Any] {
    [
        kCGWindowOwnerPID as String: NSNumber(value: Int(pid)),
        kCGWindowLayer as String: NSNumber(value: layer),
        kCGWindowBounds as String: frame.dictionaryRepresentation,
    ]
}
