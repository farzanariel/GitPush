import SwiftUI

@main
struct GitPushApp: App {
    @StateObject private var appState = AppState()

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
        .onChange(of: appState.hotkeyEnabled) { _, enabled in
            if enabled {
                registerHotkey()
            } else {
                HotkeyService.shared.unregister()
            }
        }
        .defaultSize(width: 340, height: 480)
    }

    init() {
        // Delay setup to after state is initialized
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [self] in
            appState.startScanning()
            if appState.hotkeyEnabled {
                registerHotkey()
            }
        }
    }

    private func registerHotkey() {
        HotkeyService.shared.register { [self] in
            Task { @MainActor in
                await appState.commitAndPushAll()
            }
        }
    }
}
