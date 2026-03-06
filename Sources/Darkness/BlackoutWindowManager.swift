import AppKit
import CoreGraphics

@MainActor
protocol BlackoutWindowFactory {
    func makeWindow(for display: DisplayDescriptor) -> BlackoutWindow
}

@MainActor
protocol BlackoutWindow: AnyObject {
    func setFrame(_ frame: CGRect)
    func show()
    func hide()
}

@MainActor
final class BlackoutWindowManager: BlackoutWindowManaging {
    private let factory: BlackoutWindowFactory
    private var windows: [CGDirectDisplayID: BlackoutWindow] = [:]

    init(factory: BlackoutWindowFactory = AppKitBlackoutWindowFactory()) {
        self.factory = factory
    }

    func setBlackout(_ isBlackout: Bool, for display: DisplayDescriptor) {
        if isBlackout {
            let window = windows[display.id] ?? {
                let created = factory.makeWindow(for: display)
                windows[display.id] = created
                return created
            }()

            window.setFrame(display.frame)
            window.show()
            return
        }

        windows[display.id]?.hide()
    }

    func clearAll() {
        windows.values.forEach { $0.hide() }
    }
}

@MainActor
private struct AppKitBlackoutWindowFactory: BlackoutWindowFactory {
    func makeWindow(for display: DisplayDescriptor) -> BlackoutWindow {
        AppKitBlackoutWindow(frame: display.frame)
    }
}

@MainActor
private final class AppKitBlackoutWindow: BlackoutWindow {
    private let window: NSWindow

    init(frame: CGRect) {
        window = NSWindow(
            contentRect: frame,
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        window.isOpaque = true
        window.backgroundColor = .black
        window.level = .screenSaver
        window.hasShadow = false
        window.ignoresMouseEvents = true
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        window.setFrame(frame, display: true)
    }

    func setFrame(_ frame: CGRect) {
        window.setFrame(frame, display: true)
    }

    func show() {
        window.orderFrontRegardless()
    }

    func hide() {
        window.orderOut(nil)
    }
}
