import AppKit
import ApplicationServices
import CoreGraphics

enum FocusModeToggleOutcome: Equatable {
    case activated(CGRect)
    case deactivated
    case noFocusedWindow
}

@MainActor
protocol FocusedWindowProviding {
    func focusedWindowFrame() -> CGRect?
}

@MainActor
protocol FocusOverlayManaging: AnyObject {
    func show(visibleFrame: CGRect, on displays: [DisplayDescriptor])
    func hide()
}

@MainActor
final class FocusModeController {
    private let displayInventory: DisplayInventory
    private let focusedWindowProvider: FocusedWindowProviding
    private let overlayManager: FocusOverlayManaging

    private(set) var isActive = false

    init(
        displayInventory: DisplayInventory,
        focusedWindowProvider: FocusedWindowProviding,
        overlayManager: FocusOverlayManaging
    ) {
        self.displayInventory = displayInventory
        self.focusedWindowProvider = focusedWindowProvider
        self.overlayManager = overlayManager
    }

    @discardableResult
    func toggle() -> FocusModeToggleOutcome {
        if isActive {
            overlayManager.hide()
            isActive = false
            return .deactivated
        }

        guard let rawFocusedWindowFrame = focusedWindowProvider.focusedWindowFrame() else {
            return .noFocusedWindow
        }

        let focusedWindowFrame = alignToPixelGrid(rawFocusedWindowFrame)
        guard focusedWindowFrame.width > 1, focusedWindowFrame.height > 1 else {
            return .noFocusedWindow
        }

        let displays = displayInventory.listDisplays()
        overlayManager.show(visibleFrame: focusedWindowFrame, on: displays)
        isActive = true
        return .activated(focusedWindowFrame)
    }

    func deactivateIfNeeded() {
        guard isActive else {
            return
        }
        overlayManager.hide()
        isActive = false
    }

    func alignToPixelGrid(_ frame: CGRect) -> CGRect {
        let minX = floor(frame.minX)
        let minY = floor(frame.minY)
        let maxX = ceil(frame.maxX)
        let maxY = ceil(frame.maxY)
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }
}

@MainActor
final class AccessibilityFocusedWindowProvider: FocusedWindowProviding {
    func focusedWindowFrame() -> CGRect? {
        let systemWideElement = AXUIElementCreateSystemWide()

        guard let focusedAppElement = copyElementAttribute(
            from: systemWideElement,
            key: kAXFocusedApplicationAttribute as CFString
        ) else {
            return fallbackFocusedWindowFrame()
        }

        let focusedWindowElement = copyElementAttribute(
            from: focusedAppElement,
            key: kAXFocusedWindowAttribute as CFString
        )

        return focusedWindowFrame(
            for: focusedWindowElement,
            fallback: { [self] in
                fallbackFocusedWindowFrame()
            }
        )
    }

    func focusedWindowFrame(
        for focusedWindowElement: AXUIElement?,
        fallback: () -> CGRect?
    ) -> CGRect? {
        guard let focusedWindowElement else {
            return fallback()
        }

        if let origin = copyPointAttribute(
            from: focusedWindowElement,
            key: kAXPositionAttribute as CFString
        ), let size = copySizeAttribute(
            from: focusedWindowElement,
            key: kAXSizeAttribute as CFString
        ) {
            return normalizeAccessibilityFrame(CGRect(origin: origin, size: size))
        }

        if let rawFrame = copyRectAttribute(from: focusedWindowElement, key: "AXFrame" as CFString) {
            return normalizeAccessibilityFrame(rawFrame)
        }

        return fallback()
    }

    private func copyElementAttribute(from element: AXUIElement, key: CFString) -> AXUIElement? {
        var value: CFTypeRef?
        let status = AXUIElementCopyAttributeValue(element, key, &value)
        guard status == .success,
              let value,
              CFGetTypeID(value) == AXUIElementGetTypeID() else {
            return nil
        }

        return unsafeDowncast(value, to: AXUIElement.self)
    }

    private func copyPointAttribute(from element: AXUIElement, key: CFString) -> CGPoint? {
        var value: CFTypeRef?
        let status = AXUIElementCopyAttributeValue(element, key, &value)
        guard status == .success,
              let value,
              CFGetTypeID(value) == AXValueGetTypeID() else {
            return nil
        }

        let axValue = unsafeDowncast(value, to: AXValue.self)
        guard AXValueGetType(axValue) == .cgPoint else {
            return nil
        }

        var point = CGPoint.zero
        guard AXValueGetValue(axValue, .cgPoint, &point) else {
            return nil
        }
        return point
    }

    private func copySizeAttribute(from element: AXUIElement, key: CFString) -> CGSize? {
        var value: CFTypeRef?
        let status = AXUIElementCopyAttributeValue(element, key, &value)
        guard status == .success,
              let value,
              CFGetTypeID(value) == AXValueGetTypeID() else {
            return nil
        }

        let axValue = unsafeDowncast(value, to: AXValue.self)
        guard AXValueGetType(axValue) == .cgSize else {
            return nil
        }

        var size = CGSize.zero
        guard AXValueGetValue(axValue, .cgSize, &size) else {
            return nil
        }
        return size
    }

    private func copyRectAttribute(from element: AXUIElement, key: CFString) -> CGRect? {
        var value: CFTypeRef?
        let status = AXUIElementCopyAttributeValue(element, key, &value)
        guard status == .success,
              let value,
              CFGetTypeID(value) == AXValueGetTypeID() else {
            return nil
        }

        let axValue = unsafeDowncast(value, to: AXValue.self)
        guard AXValueGetType(axValue) == .cgRect else {
            return nil
        }

        var rect = CGRect.zero
        guard AXValueGetValue(axValue, .cgRect, &rect) else {
            return nil
        }
        return rect
    }

    func convertFromTopLeftToBottomLeft(_ frame: CGRect, virtualDesktopMaxY: CGFloat) -> CGRect {
        CGRect(
            x: frame.origin.x,
            y: virtualDesktopMaxY - frame.maxY,
            width: frame.width,
            height: frame.height
        )
    }

    private func normalizeAccessibilityFrame(_ frame: CGRect) -> CGRect {
        guard let virtualDesktopMaxY = NSScreen.screens.map(\.frame.maxY).max() else {
            return frame
        }
        return convertFromTopLeftToBottomLeft(frame, virtualDesktopMaxY: virtualDesktopMaxY)
    }

    private func fallbackFocusedWindowFrame() -> CGRect? {
        guard let frontmostPID = NSWorkspace.shared.frontmostApplication?.processIdentifier,
              let virtualDesktopMaxY = NSScreen.screens.map(\.frame.maxY).max(),
              let windowInfo = CGWindowListCopyWindowInfo(
                  [.optionOnScreenOnly, .excludeDesktopElements],
                  kCGNullWindowID
              ) as? [[String: Any]] else {
            return nil
        }

        return fallbackFocusedWindowFrame(
            from: windowInfo,
            frontmostPID: frontmostPID,
            virtualDesktopMaxY: virtualDesktopMaxY
        )
    }

    func fallbackFocusedWindowFrame(
        from windowInfo: [[String: Any]],
        frontmostPID: pid_t,
        virtualDesktopMaxY: CGFloat
    ) -> CGRect? {
        for entry in windowInfo {
            guard let ownerPID = (entry[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value,
                  ownerPID == frontmostPID,
                  let layer = (entry[kCGWindowLayer as String] as? NSNumber)?.intValue,
                  layer == 0,
                  let bounds = entry[kCGWindowBounds as String] as? [String: Any],
                  let frame = CGRect(dictionaryRepresentation: bounds as CFDictionary),
                  !frame.isNull,
                  !frame.isEmpty else {
                continue
            }
            // CGWindowList is ordered front-to-back, so first valid window is the focused/frontmost one.
            return convertFromTopLeftToBottomLeft(
                frame,
                virtualDesktopMaxY: virtualDesktopMaxY
            )
        }

        return nil
    }
}

@MainActor
final class FocusOverlayManager: FocusOverlayManaging {
    let overlayOpacity: CGFloat
    let bottomCompensation: CGFloat
    let topBarVisibleFraction: CGFloat
    let focusedWindowCornerRadius: CGFloat
    private var windows: [CGDirectDisplayID: FocusOverlayWindow] = [:]

    init(
        overlayOpacity: CGFloat = 1.0,
        bottomCompensation: CGFloat = 0.0,
        topBarVisibleFraction: CGFloat = 0.0,
        focusedWindowCornerRadius: CGFloat = 12.0
    ) {
        self.overlayOpacity = overlayOpacity
        self.bottomCompensation = max(0, bottomCompensation)
        self.topBarVisibleFraction = min(max(0, topBarVisibleFraction), 1)
        self.focusedWindowCornerRadius = max(0, focusedWindowCornerRadius)
    }

    func show(visibleFrame: CGRect, on displays: [DisplayDescriptor]) {
        let compensatedFrame = compensatedFocusedFrame(visibleFrame)
        let cutoutCornerRadius = focusedCutoutCornerRadius(for: compensatedFrame)
        let focusedDisplayID = focusedDisplayID(for: compensatedFrame, displays: displays)

        let activeDisplayIDs = Set(displays.map(\.id))
        let staleIDs = windows.keys.filter { !activeDisplayIDs.contains($0) }
        for staleID in staleIDs {
            windows[staleID]?.hide()
            windows.removeValue(forKey: staleID)
        }

        for display in displays {
            let window = windows[display.id] ?? {
                let created = FocusOverlayWindow(displayFrame: display.frame, overlayOpacity: overlayOpacity)
                windows[display.id] = created
                return created
            }()

            var passthroughRects: [CGRect] = []
            if display.id == focusedDisplayID, let topLeftMenuBarRect = topLeftMenuBarRect(for: display) {
                passthroughRects.append(topLeftMenuBarRect)
            }

            let allowedFrame = contentFrameWithoutTopBar(for: display)
            window.update(
                displayFrame: display.frame,
                allowedGlobalFrame: allowedFrame,
                focusedCutoutGlobalFrame: compensatedFrame,
                focusedCutoutCornerRadius: cutoutCornerRadius,
                passthroughGlobalFrames: passthroughRects
            )
            window.show()
        }
    }

    func hide() {
        windows.values.forEach { $0.hide() }
    }

    func compensatedFocusedFrame(_ focusedFrame: CGRect) -> CGRect {
        CGRect(
            x: focusedFrame.origin.x,
            y: focusedFrame.origin.y - bottomCompensation,
            width: focusedFrame.width,
            height: focusedFrame.height + bottomCompensation
        )
    }

    func focusedCutoutCornerRadius(for focusedFrame: CGRect) -> CGFloat {
        let maxCornerRadius = min(focusedFrame.width, focusedFrame.height) / 2
        return min(focusedWindowCornerRadius, max(0, maxCornerRadius))
    }

    func topLeftMenuBarRect(for display: DisplayDescriptor) -> CGRect? {
        let topInset = topBarHeight(for: display)
        guard topInset > 0, topBarVisibleFraction > 0 else {
            return nil
        }

        return CGRect(
            x: display.frame.minX,
            y: display.frame.maxY - topInset,
            width: display.frame.width * topBarVisibleFraction,
            height: topInset
        )
    }

    func contentFrameWithoutTopBar(for display: DisplayDescriptor) -> CGRect {
        let topInset = topBarHeight(for: display)
        guard topInset > 0 else {
            return display.frame
        }

        return CGRect(
            x: display.frame.minX,
            y: display.frame.minY,
            width: display.frame.width,
            height: max(0, display.frame.height - topInset)
        )
    }

    private func topBarHeight(for display: DisplayDescriptor) -> CGFloat {
        max(0, display.frame.maxY - display.visibleFrame.maxY)
    }

    private func focusedDisplayID(for focusedFrame: CGRect, displays: [DisplayDescriptor]) -> CGDirectDisplayID? {
        let center = CGPoint(x: focusedFrame.midX, y: focusedFrame.midY)
        if let containingDisplay = displays.first(where: { $0.frame.contains(center) }) {
            return containingDisplay.id
        }

        return displays
            .map { display in
                let area = focusedFrame.intersection(display.frame).area
                return (display.id, area)
            }
            .max(by: { $0.1 < $1.1 })?
            .0
    }
}

@MainActor
private final class FocusOverlayWindow {
    private let window: NSWindow
    private let maskView: FocusMaskView

    init(displayFrame: CGRect, overlayOpacity: CGFloat) {
        window = NSWindow(
            contentRect: displayFrame,
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        window.isOpaque = false
        window.backgroundColor = .clear
        window.level = .screenSaver
        window.hasShadow = false
        window.ignoresMouseEvents = true
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]

        maskView = FocusMaskView(frame: CGRect(origin: .zero, size: displayFrame.size), overlayOpacity: overlayOpacity)
        window.contentView = maskView
    }

    func update(
        displayFrame: CGRect,
        allowedGlobalFrame: CGRect,
        focusedCutoutGlobalFrame: CGRect,
        focusedCutoutCornerRadius: CGFloat,
        passthroughGlobalFrames: [CGRect]
    ) {
        window.setFrame(displayFrame, display: true)
        maskView.frame = CGRect(origin: .zero, size: displayFrame.size)

        let allowedLocalFrame = CGRect(
            x: allowedGlobalFrame.origin.x - displayFrame.origin.x,
            y: allowedGlobalFrame.origin.y - displayFrame.origin.y,
            width: allowedGlobalFrame.width,
            height: allowedGlobalFrame.height
        ).intersection(maskView.bounds)

        func localCutout(for globalFrame: CGRect) -> CGRect? {
            let clippedGlobalFrame = globalFrame.intersection(allowedGlobalFrame)
            guard !clippedGlobalFrame.isNull, !clippedGlobalFrame.isEmpty else {
                return nil
            }

            let localFrame = CGRect(
                x: clippedGlobalFrame.origin.x - displayFrame.origin.x,
                y: clippedGlobalFrame.origin.y - displayFrame.origin.y,
                width: clippedGlobalFrame.width,
                height: clippedGlobalFrame.height
            )
            .intersection(maskView.bounds)
            .intersection(allowedLocalFrame)
            return localFrame.isNull || localFrame.isEmpty ? nil : localFrame
        }

        maskView.focusedCutoutRect = localCutout(for: focusedCutoutGlobalFrame)
        maskView.focusedCutoutCornerRadius = focusedCutoutCornerRadius
        maskView.passthroughRects = passthroughGlobalFrames.compactMap(localCutout)
    }

    func show() {
        window.orderFrontRegardless()
    }

    func hide() {
        window.orderOut(nil)
    }
}

@MainActor
private final class FocusMaskView: NSView {
    private let overlayOpacity: CGFloat
    var focusedCutoutRect: CGRect? {
        didSet {
            needsDisplay = true
        }
    }
    var focusedCutoutCornerRadius: CGFloat = 0 {
        didSet {
            needsDisplay = true
        }
    }
    var passthroughRects: [CGRect] = [] {
        didSet {
            needsDisplay = true
        }
    }

    init(frame frameRect: NSRect, overlayOpacity: CGFloat) {
        self.overlayOpacity = overlayOpacity
        super.init(frame: frameRect)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    override var isOpaque: Bool {
        false
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        let overlayColor = NSColor.black.withAlphaComponent(overlayOpacity)
        overlayColor.setFill()

        guard focusedCutoutRect != nil || !passthroughRects.isEmpty else {
            bounds.fill()
            return
        }

        let path = NSBezierPath(rect: bounds)
        if let focusedCutoutRect, !focusedCutoutRect.isEmpty {
            let radius = min(
                focusedCutoutCornerRadius,
                min(focusedCutoutRect.width, focusedCutoutRect.height) / 2
            )
            if radius > 0 {
                path.append(
                    NSBezierPath(
                        roundedRect: focusedCutoutRect,
                        xRadius: radius,
                        yRadius: radius
                    )
                )
            } else {
                path.append(NSBezierPath(rect: focusedCutoutRect))
            }
        }

        for passthroughRect in passthroughRects where !passthroughRect.isEmpty {
            path.append(NSBezierPath(rect: passthroughRect))
        }
        path.windingRule = .evenOdd
        path.fill()
    }
}

private extension CGRect {
    var area: CGFloat {
        guard !isNull, !isEmpty else {
            return 0
        }
        return width * height
    }
}
