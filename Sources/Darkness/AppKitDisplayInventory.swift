import AppKit
import CoreGraphics

@MainActor
final class AppKitDisplayInventory: DisplayInventory {
    func listDisplays() -> [DisplayDescriptor] {
        NSScreen.screens
            .compactMap { screen in
                guard let rawID = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
                    return nil
                }

                let displayID = CGDirectDisplayID(rawID.uint32Value)
                return DisplayDescriptor(
                    id: displayID,
                    name: screen.localizedName,
                    frame: screen.frame,
                    visibleFrame: screen.visibleFrame,
                    isBuiltIn: CGDisplayIsBuiltin(displayID) != 0
                )
            }
            .sorted(by: Self.leftToRightThenBottomToTop)
    }

    private static func leftToRightThenBottomToTop(_ lhs: DisplayDescriptor, _ rhs: DisplayDescriptor) -> Bool {
        if lhs.frame.minX != rhs.frame.minX {
            return lhs.frame.minX < rhs.frame.minX
        }
        return lhs.frame.minY < rhs.frame.minY
    }
}
