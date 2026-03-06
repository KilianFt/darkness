import Carbon.HIToolbox
import Dispatch
import Foundation

enum AppHotKey: UInt32 {
    case toggle = 1
    case cycleSelection = 2
    case focusWindow = 3
}

struct HotKeySpec {
    let id: UInt32
    let keyCode: UInt32
    let modifiers: UInt32
}

final class HotKeyMonitor {
    static let hotKeyPressedNotification = Notification.Name("HotKeyMonitorHotKeyPressed")
    static let hotKeyIDUserInfoKey = "hotKeyID"

    private let signature: OSType
    private var handlerRef: EventHandlerRef?
    private var registeredSpecs: [UInt32: HotKeySpec] = [:]
    private var registeredHotKeys: [UInt32: EventHotKeyRef] = [:]
    private var pendingRetryIDs: Set<UInt32> = []
    private var retryTimer: DispatchSourceTimer?

    init(signature: OSType) {
        self.signature = signature
        installEventHandler()
    }

    deinit {
        unregisterAll()
        if let handlerRef {
            RemoveEventHandler(handlerRef)
        }
    }

    @discardableResult
    func register(_ spec: HotKeySpec) -> Bool {
        registeredSpecs[spec.id] = spec
        if let existingRef = registeredHotKeys[spec.id] {
            UnregisterEventHotKey(existingRef)
            registeredHotKeys[spec.id] = nil
        }
        pendingRetryIDs.remove(spec.id)

        return attemptRegister(spec)
    }

    func unregisterAll() {
        for hotKeyRef in registeredHotKeys.values {
            UnregisterEventHotKey(hotKeyRef)
        }
        retryTimer?.cancel()
        retryTimer = nil
        pendingRetryIDs.removeAll()
        registeredSpecs.removeAll()
        registeredHotKeys.removeAll()
    }

    fileprivate func handleHotKey(id: UInt32) {
        NSLog("Darkness: received hotkey id=%u", id)
        if Thread.isMainThread {
            NotificationCenter.default.post(
                name: Self.hotKeyPressedNotification,
                object: nil,
                userInfo: [Self.hotKeyIDUserInfoKey: id]
            )
            return
        }

        DispatchQueue.main.async {
            NotificationCenter.default.post(
                name: Self.hotKeyPressedNotification,
                object: nil,
                userInfo: [Self.hotKeyIDUserInfoKey: id]
            )
        }
    }

    private func installEventHandler() {
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        let selfPointer = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        InstallEventHandler(
            GetApplicationEventTarget(),
            hotKeyEventHandler,
            1,
            &eventType,
            selfPointer,
            &handlerRef
        )
    }

    private func attemptRegister(_ spec: HotKeySpec) -> Bool {
        let hotKeyID = EventHotKeyID(signature: signature, id: spec.id)
        var hotKeyRef: EventHotKeyRef?

        let status = RegisterEventHotKey(
            spec.keyCode,
            spec.modifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )

        guard status == noErr, let hotKeyRef else {
            if Self.shouldRetryRegistrationStatus(status) {
                pendingRetryIDs.insert(spec.id)
                startRetryTimerIfNeeded()
            } else {
                pendingRetryIDs.remove(spec.id)
            }
            NSLog("Darkness: failed to register hotkey id=%u status=%d", spec.id, status)
            return false
        }

        pendingRetryIDs.remove(spec.id)
        registeredHotKeys[spec.id] = hotKeyRef
        stopRetryTimerIfIdle()
        NSLog("Darkness: registered hotkey id=%u", spec.id)
        return true
    }

    private func startRetryTimerIfNeeded() {
        guard retryTimer == nil else {
            return
        }

        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now() + .seconds(1), repeating: .seconds(2))
        timer.setEventHandler { [weak self] in
            self?.retryPendingRegistrations()
        }
        timer.resume()
        retryTimer = timer
    }

    private func retryPendingRegistrations() {
        let pendingIDs = Array(pendingRetryIDs)
        guard !pendingIDs.isEmpty else {
            stopRetryTimerIfIdle()
            return
        }

        for id in pendingIDs {
            guard let spec = registeredSpecs[id] else {
                pendingRetryIDs.remove(id)
                continue
            }
            _ = attemptRegister(spec)
        }
    }

    private func stopRetryTimerIfIdle() {
        guard pendingRetryIDs.isEmpty else {
            return
        }
        retryTimer?.cancel()
        retryTimer = nil
    }

    static func shouldRetryRegistrationStatus(_ status: OSStatus) -> Bool {
        status == eventHotKeyExistsErr
    }
}

private func hotKeyEventHandler(
    _ nextHandler: EventHandlerCallRef?,
    _ event: EventRef?,
    _ userData: UnsafeMutableRawPointer?
) -> OSStatus {
    guard let event, let userData else {
        return OSStatus(eventNotHandledErr)
    }

    var hotKeyID = EventHotKeyID()
    let status = GetEventParameter(
        event,
        EventParamName(kEventParamDirectObject),
        EventParamType(typeEventHotKeyID),
        nil,
        MemoryLayout<EventHotKeyID>.size,
        nil,
        &hotKeyID
    )

    guard status == noErr else {
        return status
    }

    let monitor = Unmanaged<HotKeyMonitor>.fromOpaque(userData).takeUnretainedValue()
    monitor.handleHotKey(id: hotKeyID.id)
    return noErr
}
