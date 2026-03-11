import AppKit
import Combine
import SwiftUI

@MainActor
let appState = AppState()

@main
struct GitPushApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private let popover = NSPopover()
    private var hostingController: NSHostingController<MenuBarView>?
    private var cancellables: Set<AnyCancellable> = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        setupPopover()
        setupStatusItem()
        observeAppState()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(userDefaultsDidChange),
            name: UserDefaults.didChangeNotification,
            object: nil
        )

        Task { @MainActor in
            appState.requestNotificationPermission()
            appState.startScanning()
            AppDelegate.setupHotkey()
            updateStatusItem()
            updatePopoverSizeFromFittingSize()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        NotificationCenter.default.removeObserver(self)
    }

    private func setupPopover() {
        let rootView = MenuBarView(appState: appState) { [weak self] size in
            self?.updatePopoverSize(to: size)
        }
        let controller = NSHostingController(rootView: rootView)
        controller.view.translatesAutoresizingMaskIntoConstraints = false
        hostingController = controller

        popover.behavior = .transient
        popover.animates = false
        popover.contentViewController = controller
    }

    private func setupStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem = item

        guard let button = item.button else { return }
        button.target = self
        button.action = #selector(togglePopover(_:))
        button.sendAction(on: [.leftMouseUp])
        updateStatusItem()
    }

    private func observeAppState() {
        appState.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] in
                DispatchQueue.main.async {
                    self?.updateStatusItem()
                    self?.updatePopoverSizeFromFittingSize()
                }
            }
            .store(in: &cancellables)
    }

    @objc
    private func togglePopover(_ sender: AnyObject?) {
        guard let button = statusItem?.button else { return }

        if popover.isShown {
            popover.performClose(sender)
            return
        }

        updatePopoverSizeFromFittingSize()
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
    }

    private func updateStatusItem() {
        guard let button = statusItem?.button else { return }

        button.image = NSImage(
            systemSymbolName: appState.menuBarIcon,
            accessibilityDescription: "GitPush"
        )
        button.imagePosition = appState.showsMenuBarCount ? .imageLeading : .imageOnly
        button.title = statusItemTitle
        button.contentTintColor = statusItemTintColor
        button.toolTip = appState.menuBarLabel.isEmpty ? "GitPush" : appState.menuBarLabel
    }

    private var statusItemTitle: String {
        if appState.showsMenuBarCount, appState.dirtyRepoCount > 0 {
            return "\(appState.dirtyRepoCount)"
        }
        return ""
    }

    private var statusItemTintColor: NSColor? {
        switch appState.menuBarStatus {
        case .idle:
            return nil
        case .committing:
            return .systemOrange
        case .pushing:
            return .systemBlue
        case .success:
            return .systemGreen
        case .error:
            return .systemRed
        }
    }

    private func updatePopoverSizeFromFittingSize() {
        guard let view = hostingController?.view else { return }
        view.layoutSubtreeIfNeeded()
        updatePopoverSize(to: view.fittingSize)
    }

    private func updatePopoverSize(to size: CGSize) {
        let clampedSize = CGSize(
            width: max(320, ceil(size.width)),
            height: max(1, ceil(size.height))
        )
        popover.contentSize = clampedSize
    }

    @objc
    private func userDefaultsDidChange() {
        Task { @MainActor in
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
