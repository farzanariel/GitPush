import SwiftUI
import Carbon

/// A key recorder view — click to start recording, press any key combo, click again to stop.
/// Inspired by Raycast, Rectangle, and Alfred's shortcut recorders.
struct HotkeyRecorderView: View {
    @Binding var keyCode: Int
    @Binding var modifiers: Int
    @State private var isRecording = false
    @State private var globalMonitor: Any?
    @State private var localMonitor: Any?

    var body: some View {
        HStack(spacing: 6) {
            Button {
                if isRecording {
                    stopRecording()
                } else {
                    startRecording()
                }
            } label: {
                HStack(spacing: 4) {
                    if isRecording {
                        Circle()
                            .fill(.red)
                            .frame(width: 6, height: 6)
                        Text("Press shortcut…")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    } else if keyCode >= 0 {
                        Text(shortcutDisplayString)
                            .font(.system(size: 11, weight: .medium, design: .rounded))
                    } else {
                        Text("Click to record")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(minWidth: 120, minHeight: 20)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(isRecording ? Color.red.opacity(0.08) : Color(nsColor: .textBackgroundColor))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .stroke(isRecording ? Color.red.opacity(0.4) : Color(nsColor: .separatorColor), lineWidth: 1)
                )
            }
            .buttonStyle(.plain)

            if keyCode >= 0 {
                Button {
                    keyCode = -1
                    modifiers = 0
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Clear shortcut")
            }
        }
    }

    private func startRecording() {
        // Unregister the active hotkey while recording so it doesn't intercept our keys
        HotkeyService.shared.unregister()
        isRecording = true

        // Use both global and local monitors to catch keys regardless of focus
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [self] event in
            handleRecordedKey(event)
        }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [self] event in
            handleRecordedKey(event)
            return nil
        }
    }

    private func handleRecordedKey(_ event: NSEvent) {
        // Escape to cancel
        if event.keyCode == 53 {
            stopRecording()
            return
        }

        // Require at least one of Cmd, Ctrl, Option
        let mods = event.modifierFlags.intersection([.command, .control, .option])
        guard !mods.isEmpty else { return }

        keyCode = Int(event.keyCode)
        modifiers = Int(event.modifierFlags.intersection([.command, .control, .option, .shift]).rawValue)
        stopRecording()
    }

    private func stopRecording() {
        isRecording = false
        if let m = globalMonitor { NSEvent.removeMonitor(m); globalMonitor = nil }
        if let m = localMonitor { NSEvent.removeMonitor(m); localMonitor = nil }
        // Re-register the hotkey (it was unregistered for recording)
        AppDelegate.setupHotkey()
    }

    var shortcutDisplayString: String {
        displayString(keyCode: keyCode, modifiers: modifiers)
    }

    static func displayString(keyCode: Int, modifiers: Int) -> String {
        let flags = NSEvent.ModifierFlags(rawValue: UInt(modifiers))
        var parts: [String] = []
        if flags.contains(.control) { parts.append("⌃") }
        if flags.contains(.option) { parts.append("⌥") }
        if flags.contains(.shift) { parts.append("⇧") }
        if flags.contains(.command) { parts.append("⌘") }
        parts.append(keyName(for: keyCode))
        return parts.joined()
    }

    private func displayString(keyCode: Int, modifiers: Int) -> String {
        Self.displayString(keyCode: keyCode, modifiers: modifiers)
    }

    private static func keyName(for keyCode: Int) -> String {
        let map: [Int: String] = [
            0: "A", 1: "S", 2: "D", 3: "F", 4: "H", 5: "G", 6: "Z", 7: "X",
            8: "C", 9: "V", 11: "B", 12: "Q", 13: "W", 14: "E", 15: "R",
            16: "Y", 17: "T", 18: "1", 19: "2", 20: "3", 21: "4", 22: "6",
            23: "5", 24: "=", 25: "9", 26: "7", 27: "-", 28: "8", 29: "0",
            30: "]", 31: "O", 32: "U", 33: "[", 34: "I", 35: "P", 37: "L",
            38: "J", 39: "'", 40: "K", 41: ";", 42: "\\", 43: ",", 44: "/",
            45: "N", 46: "M", 47: ".", 49: "Space", 50: "`",
            36: "Return", 48: "Tab", 51: "Delete", 53: "Esc",
            76: "Enter", 96: "F5", 97: "F6", 98: "F7", 99: "F3",
            100: "F8", 101: "F9", 103: "F11", 105: "F13",
            107: "F14", 109: "F10", 111: "F12", 113: "F15",
            118: "F4", 119: "F2", 120: "F1", 122: "F16",
            123: "←", 124: "→", 125: "↓", 126: "↑",
        ]
        return map[keyCode] ?? "Key\(keyCode)"
    }
}
