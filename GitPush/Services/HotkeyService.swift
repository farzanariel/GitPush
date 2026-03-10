import AppKit

class HotkeyService {
    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var callback: (() -> Void)?
    private var targetKeyCode: UInt16 = 0
    private var targetModifiers: NSEvent.ModifierFlags = []

    static let shared = HotkeyService()

    /// Register a custom hotkey
    func register(keyCode: Int, modifiers: Int, callback: @escaping () -> Void) {
        unregister()
        guard keyCode >= 0 else { return }

        self.callback = callback
        self.targetKeyCode = UInt16(keyCode)
        self.targetModifiers = NSEvent.ModifierFlags(rawValue: UInt(modifiers))
            .intersection([.command, .control, .option, .shift])

        // Global monitor — fires when other apps are focused
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.handleKeyEvent(event)
        }

        // Local monitor — fires when this app is focused
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if self?.handleKeyEvent(event) == true {
                return nil
            }
            return event
        }
    }

    @discardableResult
    private func handleKeyEvent(_ event: NSEvent) -> Bool {
        let eventMods = event.modifierFlags.intersection([.command, .control, .option, .shift])
        guard event.keyCode == targetKeyCode && eventMods == targetModifiers else {
            return false
        }
        callback?()
        return true
    }

    func unregister() {
        if let globalMonitor = globalMonitor {
            NSEvent.removeMonitor(globalMonitor)
            self.globalMonitor = nil
        }
        if let localMonitor = localMonitor {
            NSEvent.removeMonitor(localMonitor)
            self.localMonitor = nil
        }
        callback = nil
    }

    deinit {
        unregister()
    }
}
