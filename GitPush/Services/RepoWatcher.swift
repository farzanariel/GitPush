import Foundation

@MainActor
class RepoWatcher {
    private var timer: Timer?
    private weak var appState: AppState?

    init(appState: AppState) {
        self.appState = appState
    }

    func start() {
        appState?.scanRepos()
        timer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.appState?.scanRepos()
            }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }
}
