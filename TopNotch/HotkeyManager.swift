import Cocoa
import Carbon

final class HotkeyManager {
    static let shared = HotkeyManager()

    private var startStopHotKeyRef: EventHotKeyRef?
    private var toggleTeleprompterHotKeyRef: EventHotKeyRef?
    private var speedDownHotKeyRef: EventHotKeyRef?
    private var speedUpHotKeyRef: EventHotKeyRef?
    private var scrollUpHotKeyRef: EventHotKeyRef?
    private var scrollDownHotKeyRef: EventHotKeyRef?

    private var startStopHandler: (() -> Void)?
    private var toggleTeleprompterHandler: (() -> Void)?
    private var speedDownHandler: (() -> Void)?
    private var speedUpHandler: (() -> Void)?
    private var scrollUpHandler: (() -> Void)?
    private var scrollDownHandler: (() -> Void)?

    private init() { installEventHandler() }

    func registerStartStopHotkey(_ handler: @escaping () -> Void) {
        startStopHandler = handler
        registerHotkey(&startStopHotKeyRef, keyCode: kVK_ANSI_R, modifiers: cmdKey | shiftKey, id: 1)
    }

    func registerToggleTeleprompterHotkey(_ handler: @escaping () -> Void) {
        toggleTeleprompterHandler = handler
        registerHotkey(&toggleTeleprompterHotKeyRef, keyCode: kVK_ANSI_T, modifiers: cmdKey | shiftKey, id: 2)
    }

    /// Shift+Left: decrease scroll speed
    func registerSpeedDownHotkey(_ handler: @escaping () -> Void) {
        speedDownHandler = handler
        registerHotkey(&speedDownHotKeyRef, keyCode: kVK_LeftArrow, modifiers: shiftKey, id: 3)
    }

    /// Shift+Right: increase scroll speed
    func registerSpeedUpHotkey(_ handler: @escaping () -> Void) {
        speedUpHandler = handler
        registerHotkey(&speedUpHotKeyRef, keyCode: kVK_RightArrow, modifiers: shiftKey, id: 4)
    }

    /// Shift+Up: scroll text up (decrease offset)
    func registerScrollUpHotkey(_ handler: @escaping () -> Void) {
        scrollUpHandler = handler
        registerHotkey(&scrollUpHotKeyRef, keyCode: kVK_UpArrow, modifiers: shiftKey, id: 5)
    }

    /// Shift+Down: scroll text down (increase offset)
    func registerScrollDownHotkey(_ handler: @escaping () -> Void) {
        scrollDownHandler = handler
        registerHotkey(&scrollDownHotKeyRef, keyCode: kVK_DownArrow, modifiers: shiftKey, id: 6)
    }

    private func registerHotkey(_ ref: inout EventHotKeyRef?, keyCode: Int, modifiers: Int, id: UInt32) {
        if let existing = ref {
            UnregisterEventHotKey(existing)
        }
        let hotKeyID = EventHotKeyID(signature: OSType(UInt32(truncatingIfNeeded: 0x4C4C4B31)), id: id) // 'LLK1'
        RegisterEventHotKey(UInt32(keyCode), UInt32(modifiers), hotKeyID, GetEventDispatcherTarget(), 0, &ref)
    }

    private func installEventHandler() {
        let eventHandler: EventHandlerUPP = { (next, event, userData) -> OSStatus in
            var hotKeyID = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil, MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID)
            switch hotKeyID.id {
            case 1: HotkeyManager.shared.startStopHandler?()
            case 2: HotkeyManager.shared.toggleTeleprompterHandler?()
            case 3: HotkeyManager.shared.speedDownHandler?()
            case 4: HotkeyManager.shared.speedUpHandler?()
            case 5: HotkeyManager.shared.scrollUpHandler?()
            case 6: HotkeyManager.shared.scrollDownHandler?()
            default: break
            }
            return noErr
        }
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetEventDispatcherTarget(), eventHandler, 1, &eventType, nil, nil)
    }
}
