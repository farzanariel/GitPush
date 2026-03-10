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
            HStack(spacing: 4) {
                Image(systemName: appState.menuBarIcon)
                    .symbolRenderingMode(.hierarchical)
                if !appState.menuBarLabel.isEmpty {
                    Text(appState.menuBarLabel)
                        .font(.system(size: 12))
                }
            }
        }
        .menuBarExtraStyle(.window)
        .onChange(of: appState.hotkeyEnabled) { _, _ in AppDelegate.setupHotkey() }
        .onChange(of: appState.hotkeyKeyCode) { _, _ in AppDelegate.setupHotkey() }
        .onChange(of: appState.hotkeyModifiers) { _, _ in AppDelegate.setupHotkey() }
        .defaultSize(width: 340, height: 480)
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
                await appState.commitAndPushAll()
            }
        }
    }
}
