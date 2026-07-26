import Carbon.HIToolbox
import Foundation

/// Global keyboard shortcuts for Next Wallpaper (⌥⇧N) and Pause/Resume (⌥⇧P).
/// Uses the classic Carbon hotkey API — unlike NSEvent's global monitor, it needs
/// no Accessibility/Input Monitoring permission and works even when LiveWall isn't frontmost.
final class HotkeyManager {
    static let shared = HotkeyManager()

    private var hotKeyRefs: [EventHotKeyRef] = []
    private var eventHandler: EventHandlerRef?
    private var isRegistered = false

    private init() {}

    func start() {
        guard Library.shared.settings.globalHotkeysEnabled, !isRegistered else { return }
        installHandler()
        register(id: 1, keyCode: UInt32(kVK_ANSI_N), modifiers: UInt32(optionKey | shiftKey))
        register(id: 2, keyCode: UInt32(kVK_ANSI_P), modifiers: UInt32(optionKey | shiftKey))
        isRegistered = true
    }

    func stop() {
        for ref in hotKeyRefs { UnregisterEventHotKey(ref) }
        hotKeyRefs.removeAll()
        if let eventHandler { RemoveEventHandler(eventHandler) }
        eventHandler = nil
        isRegistered = false
    }

    func restart() {
        stop()
        start()
    }

    private func installHandler() {
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), liveWallHotKeyHandler, 1, &eventType, nil, &eventHandler)
    }

    private func register(id: UInt32, keyCode: UInt32, modifiers: UInt32) {
        var hotKeyRef: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(signature: fourCharCode("LWHK"), id: id)
        let status = RegisterEventHotKey(keyCode, modifiers, hotKeyID, GetApplicationEventTarget(), 0, &hotKeyRef)
        if status == noErr, let hotKeyRef { hotKeyRefs.append(hotKeyRef) }
    }
}

private func fourCharCode(_ string: String) -> FourCharCode {
    string.utf8.reduce(0) { ($0 << 8) + FourCharCode($1) }
}

private func liveWallHotKeyHandler(
    nextHandler: EventHandlerCallRef?,
    event: EventRef?,
    userData: UnsafeMutableRawPointer?
) -> OSStatus {
    guard let event else { return noErr }
    var hkID = EventHotKeyID()
    GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                       nil, MemoryLayout<EventHotKeyID>.size, nil, &hkID)
    switch hkID.id {
    case 1: DispatchQueue.main.async { WallpaperEngine.shared.nextWallpaper() }
    case 2: DispatchQueue.main.async { WallpaperEngine.shared.togglePause() }
    default: break
    }
    return noErr
}
