import Foundation
import SwiftUI

enum MenuBarStatus: Equatable {
    case idle
    case committing(repoName: String)
    case pushing(repoName: String)
    case success
    case error
}

@MainActor
class AppState: ObservableObject {
    @Published var repositories: [Repository] = []
    @Published var menuBarStatus: MenuBarStatus = .idle
    @Published var animationFrame: Int = 0

    @AppStorage("projectsPath") var projectsPath: String = "~/Documents/Projects"
    @AppStorage("aiProvider") var aiProviderRaw: String = AIProvider.openai.rawValue
    @AppStorage("hotkeyEnabled") var hotkeyEnabled: Bool = true
    @AppStorage("hotkeyKeyCode") var hotkeyKeyCode: Int = -1  // -1 = not set
    @AppStorage("hotkeyModifiers") var hotkeyModifiers: Int = 0
    @AppStorage("autoGenerateCommitMessage") var autoGenerateCommitMessage: Bool = true

    private var animationTimer: Timer?
    private var scanTimer: Timer?

    var aiProvider: AIProvider {
        get { AIProvider(rawValue: aiProviderRaw) ?? .openai }
        set { aiProviderRaw = newValue.rawValue }
    }

    /// Get the API key for the current provider from Keychain
    var currentAPIKey: String {
        let keychainKey = aiProvider == .claude ? "claude-api-key" : "openai-api-key"
        return KeychainService.load(key: keychainKey) ?? ""
    }

    /// Save an API key for a specific provider to Keychain
    func saveAPIKey(_ key: String, for provider: AIProvider) {
        let keychainKey = provider == .claude ? "claude-api-key" : "openai-api-key"
        _ = KeychainService.save(key: keychainKey, value: key)
    }

    /// Check if the current provider has a saved API key
    var hasAPIKey: Bool {
        !currentAPIKey.isEmpty
    }

    var expandedProjectsPath: String {
        (projectsPath as NSString).expandingTildeInPath
    }

    var menuBarLabel: String {
        let dots = String(repeating: ".", count: (animationFrame % 3) + 1)
        switch menuBarStatus {
        case .idle: return ""
        case .committing(let name): return "Committing \(name)\(dots)"
        case .pushing(let name): return "Pushing \(name)\(dots)"
        case .success: return ""
        case .error: return ""
        }
    }

    var menuBarIcon: String {
        switch menuBarStatus {
        case .idle: return "arrow.up.circle"
        case .committing: return "ellipsis.circle"
        case .pushing: return "icloud.and.arrow.up"
        case .success: return "checkmark.circle.fill"
        case .error: return "exclamationmark.circle.fill"
        }
    }

    func startAnimating() {
        animationTimer?.invalidate()
        animationFrame = 0
        animationTimer = Timer.scheduledTimer(withTimeInterval: 0.4, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.animationFrame += 1
            }
        }
    }

    func stopAnimating() {
        animationTimer?.invalidate()
        animationTimer = nil
        animationFrame = 0
    }

    func startScanning() {
        scanRepos()
        scanTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.scanRepos()
            }
        }
    }

    func stopScanning() {
        scanTimer?.invalidate()
        scanTimer = nil
    }

    func scanRepos() {
        guard !repositories.contains(where: { $0.operation.isInProgress }) else { return }

        Task {
            let scanned = await GitService.scanActiveRepositories(in: expandedProjectsPath)
            var updated = scanned
            for i in updated.indices {
                if let existing = repositories.first(where: { $0.id == updated[i].id }) {
                    updated[i].operation = existing.operation
                    updated[i].commitMessage = existing.commitMessage
                }
            }
            self.repositories = updated
        }
    }

    func commitAndPush(repo: Repository) async {
        guard let index = repositories.firstIndex(where: { $0.id == repo.id }) else { return }

        var message = repositories[index].commitMessage
        if message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            message = "update \(DateFormatter.shortDateTime.string(from: Date()))"
        }

        // Commit
        repositories[index].operation = .committing
        menuBarStatus = .committing(repoName: repo.name)
        startAnimating()

        let commitResult = await GitService.commit(at: repo.path, message: message)
        switch commitResult {
        case .failure(let error):
            repositories[index].operation = .error(error.message)
            menuBarStatus = .error
            stopAnimating()
            scheduleStatusReset(index: index)
            return
        case .success:
            break
        }

        // Push
        repositories[index].operation = .pushing
        menuBarStatus = .pushing(repoName: repo.name)

        let pushResult = await GitService.push(at: repo.path)
        switch pushResult {
        case .failure(let error):
            repositories[index].operation = .error(error.message)
            menuBarStatus = .error
            stopAnimating()
            scheduleStatusReset(index: index)
        case .success:
            repositories[index].operation = .success
            repositories[index].commitMessage = ""
            menuBarStatus = .success
            stopAnimating()
            scheduleStatusReset(index: index)
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
                self?.scanRepos()
            }
        }
    }

    func generateCommitMessage(for repo: Repository) async {
        guard let index = repositories.firstIndex(where: { $0.id == repo.id }) else { return }

        let diff = await GitService.diff(at: repo.path)
        guard !diff.isEmpty else {
            repositories[index].commitMessage = "update \(DateFormatter.shortDateTime.string(from: Date()))"
            return
        }

        let apiKey = currentAPIKey
        if !apiKey.isEmpty {
            do {
                let message = try await AIService.generateCommitMessage(diff: diff, apiKey: apiKey, provider: aiProvider)
                if let idx = repositories.firstIndex(where: { $0.id == repo.id }) {
                    repositories[idx].commitMessage = message
                }
            } catch {
                repositories[index].commitMessage = "update \(DateFormatter.shortDateTime.string(from: Date()))"
            }
        } else {
            repositories[index].commitMessage = "update \(DateFormatter.shortDateTime.string(from: Date()))"
        }
    }

    func commitAndPushAll() async {
        let reposWithChanges = repositories.filter { $0.changedFileCount > 0 }
        for repo in reposWithChanges {
            await commitAndPush(repo: repo)
        }
    }

    private func scheduleStatusReset(index: Int) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { [weak self] in
            guard let self = self else { return }
            if index < self.repositories.count {
                self.repositories[index].operation = .idle
            }
            if !self.repositories.contains(where: { $0.operation.isInProgress }) {
                self.menuBarStatus = .idle
            }
        }
    }
}

extension DateFormatter {
    static let shortDateTime: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm"
        return f
    }()
}
