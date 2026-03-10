import Carbon
import AppKit

class HotkeyService {
    private var hotKeyRef: EventHotKeyRef?
    private var eventHandler: EventHandlerRef?
    private static var sharedCallback: (() -> Void)?

    static let shared = HotkeyService()

    /// Register a custom global hotkey using Carbon API (no Accessibility permission needed)
    func register(keyCode: Int, modifiers: Int, callback: @escaping () -> Void) {
        unregister()
        guard keyCode >= 0 else { return }

        HotkeyService.sharedCallback = callback

        // Install Carbon event handler
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        let status = InstallEventHandler(
            GetEventDispatcherTarget(),
            { (_, inEvent, _) -> OSStatus in
                HotkeyService.sharedCallback?()
                return noErr
            },
            1,
            &eventType,
            nil,
            &eventHandler
        )
        guard status == noErr else { return }

        // Convert NSEvent modifier flags to Carbon modifiers
        let nsFlags = NSEvent.ModifierFlags(rawValue: UInt(modifiers))
        var carbonMods: UInt32 = 0
        if nsFlags.contains(.command) { carbonMods |= UInt32(cmdKey) }
        if nsFlags.contains(.option) { carbonMods |= UInt32(optionKey) }
        if nsFlags.contains(.control) { carbonMods |= UInt32(controlKey) }
        if nsFlags.contains(.shift) { carbonMods |= UInt32(shiftKey) }

        var hotKeyID = EventHotKeyID()
        hotKeyID.signature = OSType(0x47505348) // "GPSH"
        hotKeyID.id = 1

        RegisterEventHotKey(
            UInt32(keyCode),
            carbonMods,
            hotKeyID,
            GetEventDispatcherTarget(),
            0,
            &hotKeyRef
        )
    }

    func unregister() {
        if let ref = hotKeyRef {
            UnregisterEventHotKey(ref)
            hotKeyRef = nil
        }
        if let handler = eventHandler {
            RemoveEventHandler(handler)
            eventHandler = nil
        }
        HotkeyService.sharedCallback = nil
    }

    deinit {
        unregister()
    }
}
