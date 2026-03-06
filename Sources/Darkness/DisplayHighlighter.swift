import AppKit

@MainActor
protocol DisplayHighlighting: AnyObject {
    func flashHighlight(on display: DisplayDescriptor)
}

@MainActor
final class DisplayHighlighter: DisplayHighlighting {
    private var window: NSWindow?
    private var dismissTimer: Timer?

    func flashHighlight(on display: DisplayDescriptor) {
        dismissTimer?.invalidate()
        dismissTimer = nil

        if window == nil {
            let window = NSWindow(
                contentRect: display.frame,
                styleMask: .borderless,
                backing: .buffered,
                defer: false
            )
            window.isOpaque = false
            window.backgroundColor = .clear
            window.ignoresMouseEvents = true
            window.level = .statusBar
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
            window.contentView = HighlightBorderView(frame: display.frame)
            self.window = window
        }

        window?.setFrame(display.frame, display: true)
        window?.orderFrontRegardless()

        dismissTimer = Timer.scheduledTimer(
            timeInterval: 1.0,
            target: self,
            selector: #selector(hideHighlight),
            userInfo: nil,
            repeats: false
        )
    }

    @objc
    private func hideHighlight() {
        window?.orderOut(nil)
    }
}

private final class HighlightBorderView: NSView {
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        NSColor.systemYellow.setStroke()
        let border = NSBezierPath(rect: bounds.insetBy(dx: 4, dy: 4))
        border.lineWidth = 8
        border.stroke()
    }
}
