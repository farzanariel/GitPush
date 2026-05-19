import Foundation

struct GitError: Error {
    let message: String
}

actor GitService {
    private static let gitPushCoAuthorName = "GitPush"

    // Processes we consider "active work" — only matched against cwd
    private static let activeProcesses: Set<String> = [
        // Editors & IDEs
        "Cursor", "Cursor Helper", "Cursor Helper (Renderer)", "Cursor Helper (GPU)",
        "Code", "Code Helper", "Code Helper (Renderer)", "Code Helper (GPU)",
        "Electron", "Electron Helper",
        "Xcode",
        "nova", "Nova",
        "sublime_text", "Sublime Text",
        "TextEdit",
        "idea", "webstorm", "pycharm", "goland", "rubymine", "phpstorm", "clion",
        "fleet",
        "zed", "Zed",
        "BBEdit",
        "CotEditor",
        // Shells & terminals
        "zsh", "bash", "fish", "sh",
        "vim", "nvim", "nano", "emacs",
        "claude",
        "tmux", "screen",
    ]

    /// Fast scan: only checks cwd of all processes (no recursive lsof +D)
    static func scanActiveRepositories(in directory: String) async -> [Repository] {
        // lsof -d cwd lists ONLY the current working directory of every process
        // This is near-instant vs lsof +D which recursively scans all open files
        let cwdOutput = await run("lsof", args: ["-d", "cwd", "-Fcn"])

        var repoRoots = Set<String>()
        let fileManager = FileManager.default
        var currentCommand = ""

        for line in cwdOutput.split(separator: "\n") {
            let s = String(line)
            if s.hasPrefix("c") {
                currentCommand = String(s.dropFirst())
            } else if s.hasPrefix("n") {
                let path = String(s.dropFirst())
                guard activeProcesses.contains(currentCommand) && path.hasPrefix(directory) else { continue }
                collectRepoRoots(from: path, under: directory, using: fileManager, into: &repoRoots)
            }
        }

        // Strategy 2: Query terminal app windows for their working directories
        // Terminal.app and iTerm2 expose tab cwds via AppleScript
        let terminalPaths = await getTerminalWorkingDirectories(under: directory)
        for path in terminalPaths {
            collectRepoRoots(from: path, under: directory, using: fileManager, into: &repoRoots)
        }

        // Strategy 3: Find repos with recently modified .git directories (last 24h)
        // This catches repos actively being worked on even if no process cwd matches
        // (e.g., Cursor opens a folder but its cwd is elsewhere, or Claude runs from ~)
        let recentCutoff = Date().addingTimeInterval(-24 * 60 * 60)
        if let contents = try? fileManager.contentsOfDirectory(atPath: directory) {
            for item in contents {
                let repoPath = (directory as NSString).appendingPathComponent(item)
                let gitIndex = (repoPath as NSString).appendingPathComponent(".git/index")

                guard let attrs = try? fileManager.attributesOfItem(atPath: gitIndex),
                      let modified = attrs[.modificationDate] as? Date,
                      modified > recentCutoff else { continue }

                repoRoots.insert(repoPath)
            }
        }

        // Get status for each active repo (in parallel)
        let repos = await withTaskGroup(of: Repository?.self) { group in
            for repoPath in repoRoots {
                group.addTask {
                    let (branch, changedFiles) = await getStatus(at: repoPath)
                    let unpushed = await unpushedCount(at: repoPath)
                    let name = (repoPath as NSString).lastPathComponent
                    return Repository(
                        id: repoPath,
                        path: repoPath,
                        name: name,
                        branch: branch,
                        changedFileCount: changedFiles.count,
                        changedFiles: changedFiles,
                        unpushedCount: unpushed
                    )
                }
            }

            var results: [Repository] = []
            for await repo in group {
                if let repo = repo, repo.changedFileCount > 0 || repo.unpushedCount > 0 {
                    results.append(repo)
                }
            }
            return results
        }

        return repos.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    static func scanRemoteRepositories(in root: RemoteProjectRoot) async -> [Repository] {
        let quotedRoot = shellPathQuote(root.path)
        let output = await runSSH(
            host: root.host,
            command: "find \(quotedRoot) -maxdepth 3 -type d -name .git -prune -print 2>/dev/null",
            includeStderr: true
        )

        let repoPaths = Set(output
            .split(separator: "\n")
            .map { String($0) }
            .filter { $0.hasSuffix("/.git") }
            .map { String($0.dropLast(5)) }
        )

        let repos = await withTaskGroup(of: Repository?.self) { group in
            for repoPath in repoPaths {
                group.addTask {
                    let (branch, changedFiles) = await getStatus(at: repoPath, location: .remote(host: root.host))
                    let unpushed = await unpushedCount(at: repoPath, location: .remote(host: root.host))
                    let name = (repoPath as NSString).lastPathComponent
                    return Repository(
                        id: "remote:\(root.host):\(repoPath)",
                        path: repoPath,
                        name: name,
                        location: .remote(host: root.host),
                        branch: branch,
                        changedFileCount: changedFiles.count,
                        changedFiles: changedFiles,
                        unpushedCount: unpushed
                    )
                }
            }

            var results: [Repository] = []
            for await repo in group {
                if let repo = repo, repo.changedFileCount > 0 || repo.unpushedCount > 0 {
                    results.append(repo)
                }
            }
            return results
        }

        return repos.sorted {
            if $0.remoteHost == $1.remoteHost {
                return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }
            return ($0.remoteHost ?? "").localizedCaseInsensitiveCompare($1.remoteHost ?? "") == .orderedAscending
        }
    }

    private static func collectRepoRoots(
        from path: String,
        under projectsDirectory: String,
        using fileManager: FileManager,
        into repoRoots: inout Set<String>
    ) {
        if let repoRoot = findRepoRoot(from: path, stoppingAt: projectsDirectory, using: fileManager) {
            repoRoots.insert(repoRoot)
            return
        }

        for nestedRepo in findNestedRepoRoots(under: path, maxDepth: 3, using: fileManager) {
            repoRoots.insert(nestedRepo)
        }
    }

    private static func findRepoRoot(
        from path: String,
        stoppingAt projectsDirectory: String,
        using fileManager: FileManager
    ) -> String? {
        let stopPath = (projectsDirectory as NSString).standardizingPath
        var current = (path as NSString).standardizingPath

        while true {
            if isGitRepository(at: current, using: fileManager) {
                return current
            }

            if current == stopPath || current == "/" {
                return nil
            }

            let parent = (current as NSString).deletingLastPathComponent
            if parent == current {
                return nil
            }
            current = parent
        }
    }

    private static func findNestedRepoRoots(
        under path: String,
        maxDepth: Int,
        using fileManager: FileManager
    ) -> [String] {
        let baseURL = URL(fileURLWithPath: path)
        guard let enumerator = fileManager.enumerator(
            at: baseURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [],
            errorHandler: { _, _ in true }
        ) else {
            return []
        }

        let baseDepth = baseURL.pathComponents.count
        let ignoredDirectories: Set<String> = ["node_modules", ".next", "Pods", "build", "DerivedData"]
        var nestedRoots = Set<String>()

        for case let url as URL in enumerator {
            let depth = url.pathComponents.count - baseDepth
            if depth > maxDepth {
                enumerator.skipDescendants()
                continue
            }

            let name = url.lastPathComponent
            if ignoredDirectories.contains(name) {
                enumerator.skipDescendants()
                continue
            }

            if name == ".git" {
                nestedRoots.insert(url.deletingLastPathComponent().path)
                enumerator.skipDescendants()
            }
        }

        return Array(nestedRoots)
    }

    private static func isGitRepository(at path: String, using fileManager: FileManager) -> Bool {
        let gitPath = (path as NSString).appendingPathComponent(".git")
        return fileManager.fileExists(atPath: gitPath)
    }

    /// Query Terminal.app and iTerm2 for their tab working directories via AppleScript
    private static func getTerminalWorkingDirectories(under directory: String) async -> [String] {
        var paths: [String] = []

        // Terminal.app
        let terminalScript = """
        tell application "System Events"
            if exists process "Terminal" then
                tell application "Terminal"
                    set cwds to {}
                    repeat with w in windows
                        repeat with t in tabs of w
                            try
                                set end of cwds to (custom title of t)
                            end try
                        end repeat
                    end repeat
                    return cwds
                end tell
            end if
        end tell
        return {}
        """

        // iTerm2
        let itermScript = """
        tell application "System Events"
            if exists process "iTerm2" then
                tell application "iTerm2"
                    set cwds to {}
                    repeat with w in windows
                        repeat with t in tabs of w
                            repeat with s in sessions of t
                                try
                                    set p to variable named "path" of s
                                    set end of cwds to p
                                end try
                            end repeat
                        end repeat
                    end repeat
                    return cwds
                end tell
            end if
        end tell
        return {}
        """

        // Run both in parallel
        async let termPaths = runAppleScript(terminalScript)
        async let itermPaths = runAppleScript(itermScript)

        let all = await termPaths + itermPaths
        for path in all where path.hasPrefix(directory) {
            paths.append(path)
        }
        return paths
    }

    private static func runAppleScript(_ source: String) async -> [String] {
        await Task.detached {
            let process = Process()
            let pipe = Pipe()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
            process.arguments = ["-e", source]
            process.standardOutput = pipe
            process.standardError = Pipe()

            do {
                try process.run()
                process.waitUntilExit()
                let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                // osascript returns comma-separated list
                return output
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .split(separator: ",")
                    .map { $0.trimmingCharacters(in: .whitespaces) }
                    .filter { !$0.isEmpty }
            } catch {
                return []
            }
        }.value
    }

    static func getStatus(at path: String) async -> (branch: String, files: [Repository.ChangedFile]) {
        await getStatus(at: path, location: .local)
    }

    static func getStatus(at path: String, location: RepositoryLocation) async -> (branch: String, files: [Repository.ChangedFile]) {
        let branch = await runGit(location: location, path: path, args: ["rev-parse", "--abbrev-ref", "HEAD"])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let statusOutput = await runGit(location: location, path: path, args: ["status", "--porcelain"])

        let files = statusOutput.split(separator: "\n").compactMap { line -> Repository.ChangedFile? in
            let str = String(line)
            guard str.count >= 3 else { return nil }
            let status = str.prefix(2).trimmingCharacters(in: .whitespaces)
            let filePath = String(str.dropFirst(3))
            return Repository.ChangedFile(status: status, path: filePath)
        }

        return (branch.isEmpty ? "main" : branch, files)
    }

    static func unpushedCount(at path: String) async -> Int {
        await unpushedCount(at: path, location: .local)
    }

    static func unpushedCount(at path: String, location: RepositoryLocation) async -> Int {
        let output = await runGit(location: location, path: path, args: ["rev-list", "--count", "@{u}..HEAD"], includeStderr: true)
        return Int(output.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
    }

    static func diff(at path: String) async -> String {
        await diff(at: path, location: .local)
    }

    static func diff(for repo: Repository) async -> String {
        await diff(at: repo.path, location: repo.location)
    }

    static func diff(at path: String, location: RepositoryLocation) async -> String {
        let staged = await runGit(location: location, path: path, args: ["diff", "--cached"])
        let unstaged = await runGit(location: location, path: path, args: ["diff"])
        let untracked = await runGit(location: location, path: path, args: ["ls-files", "--others", "--exclude-standard"])

        var result = ""
        if !staged.isEmpty { result += staged }
        if !unstaged.isEmpty { result += "\n" + unstaged }
        if !untracked.isEmpty { result += "\nUntracked files:\n" + untracked }

        if result.count > 8000 {
            result = String(result.prefix(8000)) + "\n... (truncated)"
        }
        return result
    }

    static func commit(
        at path: String,
        message: String,
        attributeGitPush: Bool = true,
        gitPushAttributionEmail: String = "noreply@gitpush.dev"
    ) async -> Result<Void, GitError> {
        await commit(
            at: path,
            location: .local,
            message: message,
            attributeGitPush: attributeGitPush,
            gitPushAttributionEmail: gitPushAttributionEmail
        )
    }

    static func commit(
        repo: Repository,
        message: String,
        attributeGitPush: Bool = true,
        gitPushAttributionEmail: String = "noreply@gitpush.dev"
    ) async -> Result<Void, GitError> {
        await commit(
            at: repo.path,
            location: repo.location,
            message: message,
            attributeGitPush: attributeGitPush,
            gitPushAttributionEmail: gitPushAttributionEmail
        )
    }

    static func commit(
        at path: String,
        location: RepositoryLocation,
        message: String,
        attributeGitPush: Bool = true,
        gitPushAttributionEmail: String = "noreply@gitpush.dev"
    ) async -> Result<Void, GitError> {
        let addOutput = await runGit(location: location, path: path, args: ["add", "-A"], includeStderr: true)
        if addOutput.contains("fatal:") {
            return .failure(GitError(message: "Failed to stage: \(addOutput)"))
        }

        let commitMessage = attributeGitPush ? messageWithGitPushCoAuthor(message, email: gitPushAttributionEmail) : message
        let output = await runGit(location: location, path: path, args: ["commit", "-m", commitMessage], includeStderr: true)
        if output.contains("fatal:") || output.contains("error:") {
            return .failure(GitError(message: output.trimmingCharacters(in: .whitespacesAndNewlines)))
        }
        return .success(())
    }

    private static func messageWithGitPushCoAuthor(_ message: String, email: String) -> String {
        let trimmedMessage = message.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
        let gitPushCoAuthorTrailer = "Co-authored-by: \(gitPushCoAuthorName) <\(trimmedEmail)>"
        let alreadyAttributed = trimmedMessage
            .split(separator: "\n", omittingEmptySubsequences: false)
            .contains { $0.trimmingCharacters(in: .whitespacesAndNewlines).caseInsensitiveCompare(gitPushCoAuthorTrailer) == .orderedSame }

        guard !trimmedEmail.isEmpty, !alreadyAttributed else { return trimmedMessage }
        return "\(trimmedMessage)\n\n\(gitPushCoAuthorTrailer)"
    }

    static func push(at path: String) async -> Result<Void, GitError> {
        await push(at: path, location: .local)
    }

    static func push(repo: Repository) async -> Result<Void, GitError> {
        await push(at: repo.path, location: repo.location)
    }

    static func push(at path: String, location: RepositoryLocation) async -> Result<Void, GitError> {
        let output = await runGit(location: location, path: path, args: ["push"], includeStderr: true)
        if output.contains("fatal:") || output.contains("error:") {
            let branch = await runGit(location: location, path: path, args: ["rev-parse", "--abbrev-ref", "HEAD"])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let retryOutput = await runGit(location: location, path: path, args: ["push", "-u", "origin", branch], includeStderr: true)
            if retryOutput.contains("fatal:") || retryOutput.contains("error:") {
                return .failure(GitError(message: retryOutput.trimmingCharacters(in: .whitespacesAndNewlines)))
            }
        }
        return .success(())
    }

    private static func runGit(
        location: RepositoryLocation,
        path: String,
        args: [String],
        includeStderr: Bool = false
    ) async -> String {
        switch location {
        case .local:
            return await run("git", args: ["-C", path] + args, includeStderr: includeStderr)
        case .remote(let host):
            let command = (["git", "-C", shellPathQuote(path)] + args.map(shellQuote)).joined(separator: " ")
            return await runSSH(host: host, command: command, includeStderr: includeStderr)
        }
    }

    private static func runSSH(host: String, command: String, includeStderr: Bool = false) async -> String {
        await run(
            "ssh",
            args: ["-o", "BatchMode=yes", "-o", "ConnectTimeout=4", host, command],
            includeStderr: includeStderr
        )
    }

    private static func shellQuote(_ value: String) -> String {
        "'\(value.replacingOccurrences(of: "'", with: "'\\''"))'"
    }

    private static func shellPathQuote(_ value: String) -> String {
        if value == "~" {
            return "~"
        }

        if value.hasPrefix("~/") {
            return "~/" + shellQuote(String(value.dropFirst(2)))
        }

        return shellQuote(value)
    }

    private static func run(_ command: String, args: [String], includeStderr: Bool = false) async -> String {
        await Task.detached {
            let process = Process()
            let pipe = Pipe()
            let errorPipe = Pipe()

            // Build a proper PATH — menu bar apps don't inherit shell PATH
            var env = ProcessInfo.processInfo.environment
            let extraPaths = ["/usr/local/bin", "/opt/homebrew/bin", "/usr/bin", "/bin"]
            let currentPath = env["PATH"] ?? "/usr/bin:/bin"
            env["PATH"] = (extraPaths + [currentPath]).joined(separator: ":")

            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            process.arguments = [command] + args
            process.standardOutput = pipe
            process.standardError = errorPipe
            process.environment = env

            do {
                try process.run()

                // Read pipe data BEFORE waitUntilExit to avoid deadlock
                // when output exceeds the pipe buffer (~64KB)
                var output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                if includeStderr {
                    let errOutput = String(data: errorPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                    if !errOutput.isEmpty { output += "\n" + errOutput }
                }

                process.waitUntilExit()
                return output
            } catch {
                return ""
            }
        }.value
    }
}
