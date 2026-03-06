import CoreGraphics

struct DisplayDescriptor: Equatable {
    let id: CGDirectDisplayID
    let name: String
    let frame: CGRect
    let visibleFrame: CGRect
    let isBuiltIn: Bool

    var isExternal: Bool {
        !isBuiltIn
    }

    var menuTitle: String {
        "\(name) (\(Int(frame.width))x\(Int(frame.height)))"
    }
}

@MainActor
protocol DisplayInventory {
    func listDisplays() -> [DisplayDescriptor]
}

@MainActor
protocol BlackoutWindowManaging: AnyObject {
    func setBlackout(_ isBlackout: Bool, for display: DisplayDescriptor)
    func clearAll()
}

enum ToggleOutcome: Equatable {
    case noExternalDisplays
    case turnedOff(DisplayDescriptor)
    case turnedOn(DisplayDescriptor)
}

@MainActor
final class DisplayStateController {
    private let inventory: DisplayInventory
    private let blackoutManager: BlackoutWindowManaging
    private(set) var externalDisplays: [DisplayDescriptor] = []

    private(set) var selectedDisplayID: CGDirectDisplayID?
    private(set) var activeBlackoutDisplayID: CGDirectDisplayID?

    init(inventory: DisplayInventory, blackoutManager: BlackoutWindowManaging) {
        self.inventory = inventory
        self.blackoutManager = blackoutManager
    }

    @discardableResult
    func refreshDisplays() -> [DisplayDescriptor] {
        let displays = inventory.listDisplays().filter(\.isExternal)
        externalDisplays = displays

        guard !displays.isEmpty else {
            selectedDisplayID = nil
            if activeBlackoutDisplayID != nil {
                blackoutManager.clearAll()
                activeBlackoutDisplayID = nil
            }
            return displays
        }

        if selectedDisplayID == nil || !displays.contains(where: { $0.id == selectedDisplayID }) {
            selectedDisplayID = displays.first?.id
        }

        if let activeBlackoutDisplayID,
           !displays.contains(where: { $0.id == activeBlackoutDisplayID }) {
            blackoutManager.clearAll()
            self.activeBlackoutDisplayID = nil
        }

        return displays
    }

    func selectedDisplay() -> DisplayDescriptor? {
        guard let selectedDisplayID else {
            return nil
        }
        return externalDisplays.first(where: { $0.id == selectedDisplayID })
    }

    @discardableResult
    func select(displayID: CGDirectDisplayID) -> DisplayDescriptor? {
        refreshDisplays()
        guard externalDisplays.contains(where: { $0.id == displayID }) else {
            return nil
        }
        selectedDisplayID = displayID
        return selectedDisplay()
    }

    @discardableResult
    func cycleSelection() -> DisplayDescriptor? {
        refreshDisplays()
        guard !externalDisplays.isEmpty else {
            return nil
        }

        guard let selectedDisplayID,
              let selectedIndex = externalDisplays.firstIndex(where: { $0.id == selectedDisplayID }) else {
            self.selectedDisplayID = externalDisplays[0].id
            return externalDisplays[0]
        }

        let nextIndex = (selectedIndex + 1) % externalDisplays.count
        self.selectedDisplayID = externalDisplays[nextIndex].id
        return externalDisplays[nextIndex]
    }

    @discardableResult
    func toggleSelectedDisplay() -> ToggleOutcome {
        refreshDisplays()
        guard let selectedDisplay = selectedDisplay() else {
            return .noExternalDisplays
        }

        if activeBlackoutDisplayID == selectedDisplay.id {
            blackoutManager.setBlackout(false, for: selectedDisplay)
            activeBlackoutDisplayID = nil
            return .turnedOn(selectedDisplay)
        }

        if let activeBlackoutDisplayID,
           activeBlackoutDisplayID != selectedDisplay.id {
            if let activeDisplay = externalDisplays.first(where: { $0.id == activeBlackoutDisplayID }) {
                blackoutManager.setBlackout(false, for: activeDisplay)
            } else {
                blackoutManager.clearAll()
            }
        }

        blackoutManager.setBlackout(true, for: selectedDisplay)
        activeBlackoutDisplayID = selectedDisplay.id
        return .turnedOff(selectedDisplay)
    }

    func deactivateBlackoutIfNeeded() {
        guard let activeBlackoutDisplayID else {
            return
        }

        refreshDisplays()

        if let activeDisplay = externalDisplays.first(where: { $0.id == activeBlackoutDisplayID }) {
            blackoutManager.setBlackout(false, for: activeDisplay)
        } else {
            blackoutManager.clearAll()
        }

        self.activeBlackoutDisplayID = nil
    }
}
