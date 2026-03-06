import AppKit

@MainActor
protocol ApplicationType: AnyObject {
    var delegate: NSApplicationDelegate? { get set }
    @discardableResult
    func setActivationPolicy(_ activationPolicy: NSApplication.ActivationPolicy) -> Bool
    func run()
}

extension NSApplication: ApplicationType {}

@MainActor
enum AppBootstrap {
    private(set) static var retainedDelegate: NSApplicationDelegate?

    static func configure(app: ApplicationType, delegate: NSApplicationDelegate = AppDelegate()) {
        retainedDelegate = delegate
        app.delegate = delegate
        _ = app.setActivationPolicy(.accessory)
    }
}

@main
@MainActor
enum DarknessApp {
    static func main() {
        let app = NSApplication.shared
        AppBootstrap.configure(app: app)
        app.run()
    }
}
