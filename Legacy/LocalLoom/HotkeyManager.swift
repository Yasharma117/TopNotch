import Cocoa
import Carbon

final class HotkeyManager {
    static let shared = HotkeyManager()

    private var startStopHotKeyRef: EventHotKeyRef?
    private var toggleTeleprompterHotKeyRef: EventHotKeyRef?

    private var startStopHandler: (() -> Void)?
    private var toggleTeleprompterHandler: (() -> Void)?

    private init() { installEventHandler() }

    func registerStartStopHotkey(_ handler: @escaping () -> Void) {
        startStopHandler = handler
        registerHotkey(&startStopHotKeyRef, keyCode: kVK_ANSI_R, modifiers: cmdKey | shiftKey, id: 1)
    }

    func registerToggleTeleprompterHotkey(_ handler: @escaping () -> Void) {
        toggleTeleprompterHandler = handler
        registerHotkey(&toggleTeleprompterHotKeyRef, keyCode: kVK_ANSI_T, modifiers: cmdKey | shiftKey, id: 2)
    }

    private func registerHotkey(_ ref: inout EventHotKeyRef?, keyCode: Int, modifiers: Int, id: UInt32) {
        var hotKeyID = EventHotKeyID(signature: OSType(UInt32(truncatingIfNeeded: 0x4C4C4B31)), id: id) // 'LLK1'
        RegisterEventHotKey(UInt32(keyCode), UInt32(modifiers), hotKeyID, GetEventDispatcherTarget(), 0, &ref)
    }

    private func installEventHandler() {
        let eventHandler: EventHandlerUPP = { (next, event, userData) -> OSStatus in
            var hotKeyID = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil, MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID)
            let id = hotKeyID.id
            if id == 1 {
                HotkeyManager.shared.startStopHandler?()
            } else if id == 2 {
                HotkeyManager.shared.toggleTeleprompterHandler?()
            }
            return noErr
        }
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetEventDispatcherTarget(), eventHandler, 1, &eventType, nil, nil)
    }
}
