import SwiftUI

@MainActor
let appState = AppState()

@main
struct GitPushApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra {
            MenuBarView(appState: appState)
        } label: {
            MenuBarLabelView(appState: appState)
        }
        .menuBarExtraStyle(.window)
        .onChange(of: appState.hotkeyEnabled) { _, _ in AppDelegate.setupHotkey() }
        .onChange(of: appState.hotkeyKeyCode) { _, _ in AppDelegate.setupHotkey() }
        .onChange(of: appState.hotkeyModifiers) { _, _ in AppDelegate.setupHotkey() }
        .defaultSize(width: 340, height: 480)
    }
}

struct MenuBarLabelView: View {
    @ObservedObject var appState: AppState

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: appState.menuBarIcon)
                .symbolRenderingMode(.hierarchical)
            if !appState.menuBarLabel.isEmpty {
                Text(appState.menuBarLabel)
                    .font(.system(size: 12))
            } else if appState.dirtyRepoCount > 0 {
                Text("\(appState.dirtyRepoCount)")
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
            }
        }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        // Start scanning and hotkey immediately at launch — not on popover open
        Task { @MainActor in
            appState.requestNotificationPermission()
            appState.startScanning()
            AppDelegate.setupHotkey()
        }
    }

    @MainActor
    static func setupHotkey() {
        guard appState.hotkeyEnabled, appState.hotkeyKeyCode >= 0 else {
            HotkeyService.shared.unregister()
            return
        }
        HotkeyService.shared.register(
            keyCode: appState.hotkeyKeyCode,
            modifiers: appState.hotkeyModifiers
        ) {
            Task { @MainActor in
                // Hotkey = commit only, Hotkey + Shift = commit & push
                let shiftHeld = NSEvent.modifierFlags.contains(.shift)
                if shiftHeld {
                    await appState.commitAndPushAll()
                } else {
                    await appState.commitAll()
                }
            }
        }
    }
}
