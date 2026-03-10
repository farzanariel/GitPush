import SwiftUI

@main
struct GitPushApp: App {
    @StateObject private var appState = AppState()
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra {
            MenuBarView(appState: appState)
                .onAppear {
                    appState.startScanning()
                    setupHotkey()
                }
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
        .onChange(of: appState.hotkeyEnabled) { _, _ in setupHotkey() }
        .onChange(of: appState.hotkeyKeyCode) { _, _ in setupHotkey() }
        .onChange(of: appState.hotkeyModifiers) { _, _ in setupHotkey() }
        .defaultSize(width: 340, height: 480)
    }

    private func setupHotkey() {
        guard appState.hotkeyEnabled, appState.hotkeyKeyCode >= 0 else {
            HotkeyService.shared.unregister()
            return
        }
        let state = appState
        HotkeyService.shared.register(
            keyCode: state.hotkeyKeyCode,
            modifiers: state.hotkeyModifiers
        ) {
            Task { @MainActor in
                await state.commitAndPushAll()
            }
        }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }
}
