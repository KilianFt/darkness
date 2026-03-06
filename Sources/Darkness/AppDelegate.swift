import AppKit
import ApplicationServices
import Carbon.HIToolbox
import CoreGraphics

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let displayController: DisplayStateController
    private let focusModeController: FocusModeController
    private let highlighter: DisplayHighlighting
    private let hotKeyMonitor = HotKeyMonitor(signature: 0x44524B4E) // DRKN

    private let menu = NSMenu()
    private var statusItem: NSStatusItem?

    override init() {
        let inventory = AppKitDisplayInventory()
        let blackoutManager = BlackoutWindowManager()
        let focusedWindowProvider = AccessibilityFocusedWindowProvider()
        let focusOverlayManager = FocusOverlayManager(
            overlayOpacity: 1.0,
            bottomCompensation: 0.0,
            topBarVisibleFraction: 0.0
        )
        displayController = DisplayStateController(
            inventory: inventory,
            blackoutManager: blackoutManager
        )
        focusModeController = FocusModeController(
            displayInventory: inventory,
            focusedWindowProvider: focusedWindowProvider,
            overlayManager: focusOverlayManager
        )
        highlighter = DisplayHighlighter()
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        requestPermissionsIfNeeded()
        configureStatusItem()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleHotKeyNotification(_:)),
            name: HotKeyMonitor.hotKeyPressedNotification,
            object: nil
        )
        registerHotKeys()
        rebuildMenu()
    }

    private func requestPermissionsIfNeeded() {
        let hasInputMonitoring = CGPreflightListenEventAccess()
        if !hasInputMonitoring {
            _ = CGRequestListenEventAccess()
        }

        let hasAccessibility = AXIsProcessTrusted()
        if !hasAccessibility {
            let key = "AXTrustedCheckOptionPrompt"
            _ = AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
        }

        NSLog(
            "Darkness: permissions accessibility=%@ inputMonitoring=%@",
            hasAccessibility ? "granted" : "denied",
            hasInputMonitoring ? "granted" : "denied"
        )
    }

    func applicationWillTerminate(_ notification: Notification) {
        NotificationCenter.default.removeObserver(
            self,
            name: HotKeyMonitor.hotKeyPressedNotification,
            object: nil
        )
        hotKeyMonitor.unregisterAll()
    }

    func menuWillOpen(_ menu: NSMenu) {
        rebuildMenu()
    }

    private func configureStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = item.button {
            if let image = NSImage(systemSymbolName: "display", accessibilityDescription: "Darkness") {
                image.isTemplate = true
                button.image = image
            } else {
                button.title = "Darkness"
            }
            button.toolTip = "Darkness"
        }
        menu.delegate = self
        item.menu = menu
        statusItem = item
    }

    private func registerHotKeys() {
        let modifiers = UInt32(controlKey) | UInt32(optionKey) | UInt32(cmdKey)

        _ = hotKeyMonitor.register(
            HotKeySpec(
                id: AppHotKey.toggle.rawValue,
                keyCode: UInt32(kVK_ANSI_B),
                modifiers: modifiers
            )
        )

        _ = hotKeyMonitor.register(
            HotKeySpec(
                id: AppHotKey.cycleSelection.rawValue,
                keyCode: UInt32(kVK_ANSI_N),
                modifiers: modifiers
            )
        )

        _ = hotKeyMonitor.register(
            HotKeySpec(
                id: AppHotKey.focusWindow.rawValue,
                keyCode: UInt32(kVK_ANSI_F),
                modifiers: modifiers
            )
        )
    }

    private func handleHotKey(_ id: UInt32) {
        guard let hotKey = AppHotKey(rawValue: id) else {
            NSLog("Darkness: unknown hotkey id=%u", id)
            return
        }

        NSLog("Darkness: handling hotkey id=%u", id)
        switch hotKey {
        case .toggle:
            toggleSelectedDisplay()
        case .cycleSelection:
            selectNextDisplay()
        case .focusWindow:
            toggleFocusWindowMode()
        }
    }

    @objc
    private func handleHotKeyNotification(_ notification: Notification) {
        let rawValue = notification.userInfo?[HotKeyMonitor.hotKeyIDUserInfoKey]
        let rawID: UInt32?

        if let id = rawValue as? UInt32 {
            rawID = id
        } else if let number = rawValue as? NSNumber {
            rawID = number.uint32Value
        } else {
            rawID = nil
        }

        guard let rawID else {
            return
        }
        handleHotKey(rawID)
    }

    private func rebuildMenu() {
        menu.removeAllItems()
        let displays = displayController.refreshDisplays()

        if displays.isEmpty {
            let noDisplaysItem = NSMenuItem(title: "No external displays detected", action: nil, keyEquivalent: "")
            noDisplaysItem.isEnabled = false
            menu.addItem(noDisplaysItem)
        } else {
            for display in displays {
                var title = display.menuTitle
                if displayController.activeBlackoutDisplayID == display.id {
                    title += " - blacked out"
                }

                let item = NSMenuItem(
                    title: title,
                    action: #selector(selectDisplayFromMenu(_:)),
                    keyEquivalent: ""
                )
                item.target = self
                item.representedObject = NSNumber(value: display.id)
                item.state = displayController.selectedDisplayID == display.id ? .on : .off
                menu.addItem(item)
            }
        }

        menu.addItem(.separator())

        let toggleItem = NSMenuItem(
            title: "Toggle Selected Display (Ctrl+Opt+Cmd+B)",
            action: #selector(toggleSelectedDisplay),
            keyEquivalent: ""
        )
        toggleItem.target = self
        toggleItem.isEnabled = !displays.isEmpty
        menu.addItem(toggleItem)

        let cycleItem = NSMenuItem(
            title: "Highlight Next Display (Ctrl+Opt+Cmd+N)",
            action: #selector(selectNextDisplay),
            keyEquivalent: ""
        )
        cycleItem.target = self
        cycleItem.isEnabled = displays.count > 1
        menu.addItem(cycleItem)

        let focusItem = NSMenuItem(
            title: "Toggle Focus Window (Ctrl+Opt+Cmd+F)",
            action: #selector(toggleFocusWindowMode),
            keyEquivalent: ""
        )
        focusItem.target = self
        focusItem.state = focusModeController.isActive ? .on : .off
        menu.addItem(focusItem)

        menu.addItem(.separator())
        let quitItem = NSMenuItem(title: "Quit", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)
    }

    @objc
    private func selectDisplayFromMenu(_ sender: NSMenuItem) {
        guard let value = sender.representedObject as? NSNumber else {
            return
        }

        if let display = displayController.select(displayID: value.uint32Value) {
            highlighter.flashHighlight(on: display)
        }
        rebuildMenu()
    }

    @objc
    private func toggleSelectedDisplay() {
        focusModeController.deactivateIfNeeded()
        let outcome = displayController.toggleSelectedDisplay()
        NSLog("Darkness: toggle display outcome=%@", String(describing: outcome))
        rebuildMenu()
    }

    @objc
    private func selectNextDisplay() {
        if let display = displayController.cycleSelection() {
            NSLog("Darkness: selected display id=%u name=%@", display.id, display.name)
            highlighter.flashHighlight(on: display)
        } else {
            NSLog("Darkness: no display available for selection")
        }
        rebuildMenu()
    }

    @objc
    private func toggleFocusWindowMode() {
        if !focusModeController.isActive {
            displayController.deactivateBlackoutIfNeeded()
        }

        let outcome = focusModeController.toggle()
        NSLog("Darkness: focus mode outcome=%@", String(describing: outcome))
        rebuildMenu()
    }

    @objc
    private func quit() {
        NSApplication.shared.terminate(nil)
    }
}
