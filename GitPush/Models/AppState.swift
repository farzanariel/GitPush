import Foundation
import SwiftUI
import UserNotifications

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

    var dirtyRepoCount: Int {
        repositories.filter { $0.changedFileCount > 0 }.count
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
        case .idle:
            return dirtyRepoCount > 0 ? "arrow.up.circle.fill" : "arrow.up.circle"
        case .committing:
            let frames = [
                "arrow.up.circle",
                "arrow.up.circle.badge.clock",
                "arrow.up.circle.fill",
                "arrow.up.circle.badge.clock"
            ]
            return frames[animationFrame % frames.count]
        case .pushing:
            let frames = [
                "arrow.up",
                "arrow.up.circle",
                "arrow.up.circle.fill"
            ]
            return frames[animationFrame % frames.count]
        case .success: return "checkmark.circle.fill"
        case .error: return "exclamationmark.circle.fill"
        }
    }

    var menuBarTooltip: String {
        if !menuBarLabel.isEmpty {
            return menuBarLabel
        }
        if dirtyRepoCount > 0 {
            return "\(dirtyRepoCount) repo\(dirtyRepoCount == 1 ? "" : "s") ready for commit or push"
        }
        return "GitPush"
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

    func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    private func sendNotification(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
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

    private func repoIndex(_ id: String) -> Int? {
        repositories.firstIndex(where: { $0.id == id })
    }

    func commitOnly(repo: Repository, autoGenerate: Bool = false) async {
        guard let idx = repoIndex(repo.id) else { return }

        // Show immediate feedback before AI generation
        repositories[idx].operation = .committing
        menuBarStatus = .committing(repoName: repo.name)
        startAnimating()

        if autoGenerate || repositories[idx].commitMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            await generateCommitMessage(for: repo)
        }

        guard let idx = repoIndex(repo.id) else { return }

        var message = repositories[idx].commitMessage
        if message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            message = "update \(DateFormatter.shortDateTime.string(from: Date()))"
        }

        let commitResult = await GitService.commit(at: repo.path, message: message)
        guard let idx = repoIndex(repo.id) else { return }
        switch commitResult {
        case .failure(let error):
            repositories[idx].operation = .error(error.message)
            menuBarStatus = .error
            stopAnimating()
            scheduleStatusReset(repoID: repo.id)
        case .success:
            repositories[idx].operation = .success
            repositories[idx].commitMessage = ""
            menuBarStatus = .success
            stopAnimating()
            scheduleStatusReset(repoID: repo.id)
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
                self?.scanRepos()
            }
        }
    }

    func commitAndPush(repo: Repository, autoGenerate: Bool = false) async {
        guard let idx = repoIndex(repo.id) else { return }

        // Show immediate feedback before AI generation
        repositories[idx].operation = .committing
        menuBarStatus = .committing(repoName: repo.name)
        startAnimating()

        if autoGenerate || repositories[idx].commitMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            await generateCommitMessage(for: repo)
        }

        guard let idx = repoIndex(repo.id) else { return }

        var message = repositories[idx].commitMessage
        if message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            message = "update \(DateFormatter.shortDateTime.string(from: Date()))"
        }

        let commitResult = await GitService.commit(at: repo.path, message: message)
        guard let idx = repoIndex(repo.id) else { return }
        switch commitResult {
        case .failure(let error):
            repositories[idx].operation = .error(error.message)
            menuBarStatus = .error
            stopAnimating()
            scheduleStatusReset(repoID: repo.id)
            return
        case .success:
            break
        }

        // Push
        guard let idx = repoIndex(repo.id) else { return }
        repositories[idx].operation = .pushing
        menuBarStatus = .pushing(repoName: repo.name)

        let pushResult = await GitService.push(at: repo.path)
        guard let idx = repoIndex(repo.id) else { return }
        switch pushResult {
        case .failure(let error):
            repositories[idx].operation = .error(error.message)
            menuBarStatus = .error
            stopAnimating()
            scheduleStatusReset(repoID: repo.id)
        case .success:
            repositories[idx].operation = .success
            repositories[idx].commitMessage = ""
            menuBarStatus = .success
            stopAnimating()
            scheduleStatusReset(repoID: repo.id)
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
                self?.scanRepos()
            }
        }
    }

    func pushOnly(repo: Repository) async {
        guard let idx = repoIndex(repo.id) else { return }
        repositories[idx].operation = .pushing
        menuBarStatus = .pushing(repoName: repo.name)
        startAnimating()

        let pushResult = await GitService.push(at: repo.path)
        guard let idx = repoIndex(repo.id) else { return }
        switch pushResult {
        case .failure(let error):
            repositories[idx].operation = .error(error.message)
            menuBarStatus = .error
            stopAnimating()
            scheduleStatusReset(repoID: repo.id)
        case .success:
            repositories[idx].operation = .success
            menuBarStatus = .success
            stopAnimating()
            scheduleStatusReset(repoID: repo.id)
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
                self?.scanRepos()
            }
        }
    }

    private func debugLog(_ msg: String) {
        let url = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("GitPush/debug.log")
        let line = "[\(Date())] \(msg)\n"
        if let data = line.data(using: .utf8) {
            if FileManager.default.fileExists(atPath: url.path) {
                if let handle = try? FileHandle(forWritingTo: url) {
                    handle.seekToEndOfFile()
                    handle.write(data)
                    handle.closeFile()
                }
            } else {
                try? data.write(to: url)
            }
        }
    }

    func generateCommitMessage(for repo: Repository) async {
        guard repoIndex(repo.id) != nil else {
            debugLog("generateCommitMessage: repo not found \(repo.id)")
            return
        }

        let diff = await GitService.diff(at: repo.path)
        guard !diff.isEmpty else {
            debugLog("generateCommitMessage: diff is EMPTY for \(repo.name)")
            if let idx = repoIndex(repo.id) {
                repositories[idx].commitMessage = "update \(DateFormatter.shortDateTime.string(from: Date()))"
            }
            return
        }

        debugLog("generateCommitMessage: diff length=\(diff.count) for \(repo.name)")

        let apiKey = currentAPIKey
        if !apiKey.isEmpty {
            debugLog("generateCommitMessage: calling \(aiProvider) API")
            do {
                let message = try await AIService.generateCommitMessage(diff: diff, apiKey: apiKey, provider: aiProvider)
                debugLog("generateCommitMessage: AI returned: \(message.prefix(80))")
                if let idx = repoIndex(repo.id) {
                    repositories[idx].commitMessage = message
                }
            } catch {
                debugLog("generateCommitMessage: AI error: \(error)")
                if let idx = repoIndex(repo.id) {
                    repositories[idx].commitMessage = "update \(DateFormatter.shortDateTime.string(from: Date()))"
                }
            }
        } else {
            debugLog("generateCommitMessage: no API key")
            if let idx = repoIndex(repo.id) {
                repositories[idx].commitMessage = "update \(DateFormatter.shortDateTime.string(from: Date()))"
            }
        }
    }

    func commitAll() async {
        let reposWithChanges = repositories.filter { $0.changedFileCount > 0 }
        guard !reposWithChanges.isEmpty else { return }

        for repo in reposWithChanges {
            await commitOnly(repo: repo, autoGenerate: true)
        }
    }

    func commitAndPushAll() async {
        let reposWithChanges = repositories.filter { $0.changedFileCount > 0 }
        guard !reposWithChanges.isEmpty else { return }

        for repo in reposWithChanges {
            await commitAndPush(repo: repo, autoGenerate: true)
        }
    }

    private func scheduleStatusReset(repoID: String) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { [weak self] in
            guard let self = self else { return }
            if let idx = self.repoIndex(repoID) {
                self.repositories[idx].operation = .idle
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
