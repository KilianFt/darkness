import AppKit
import XCTest
@testable import Darkness

@MainActor
final class AppBootstrapTests: XCTestCase {
    func testConfigureRetainsDelegateAndSetsAccessoryPolicy() {
        let app = FakeApplication()
        let delegate = StubDelegate()

        AppBootstrap.configure(app: app, delegate: delegate)

        XCTAssertTrue(app.delegate === delegate)
        XCTAssertTrue(AppBootstrap.retainedDelegate === delegate)
        XCTAssertEqual(app.lastPolicy, .accessory)
    }
}

@MainActor
private final class FakeApplication: ApplicationType {
    var delegate: NSApplicationDelegate?
    var lastPolicy: NSApplication.ActivationPolicy?

    @discardableResult
    func setActivationPolicy(_ activationPolicy: NSApplication.ActivationPolicy) -> Bool {
        lastPolicy = activationPolicy
        return true
    }

    func run() {}
}

private final class StubDelegate: NSObject, NSApplicationDelegate {}
