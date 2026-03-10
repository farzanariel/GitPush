import Foundation

struct GitError: Error {
    let message: String
}

actor GitService {
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

                // Walk up to find repo root
                var current = path
                while current != directory && current != "/" {
                    let gitDir = (current as NSString).appendingPathComponent(".git")
                    var isDir: ObjCBool = false
                    if fileManager.fileExists(atPath: gitDir, isDirectory: &isDir), isDir.boolValue {
                        repoRoots.insert(current)
                        break
                    }
                    current = (current as NSString).deletingLastPathComponent
                }
            }
        }

        // Strategy 2: Query terminal app windows for their working directories
        // Terminal.app and iTerm2 expose tab cwds via AppleScript
        let terminalPaths = await getTerminalWorkingDirectories(under: directory)
        for path in terminalPaths {
            var current = path
            while current != directory && current != "/" {
                let gitDir = (current as NSString).appendingPathComponent(".git")
                var isDir: ObjCBool = false
                if fileManager.fileExists(atPath: gitDir, isDirectory: &isDir), isDir.boolValue {
                    repoRoots.insert(current)
                    break
                }
                current = (current as NSString).deletingLastPathComponent
            }
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
                    let name = (repoPath as NSString).lastPathComponent
                    return Repository(
                        id: repoPath,
                        path: repoPath,
                        name: name,
                        branch: branch,
                        changedFileCount: changedFiles.count,
                        changedFiles: changedFiles
                    )
                }
            }

            var results: [Repository] = []
            for await repo in group {
                // Only include repos that have changes
                if let repo = repo, repo.changedFileCount > 0 { results.append(repo) }
            }
            return results
        }

        return repos.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    static func getStatus(at path: String) async -> (branch: String, files: [Repository.ChangedFile]) {
        let branch = await run("git", args: ["-C", path, "rev-parse", "--abbrev-ref", "HEAD"])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let statusOutput = await run("git", args: ["-C", path, "status", "--porcelain"])

        let files = statusOutput.split(separator: "\n").compactMap { line -> Repository.ChangedFile? in
            let str = String(line)
            guard str.count >= 3 else { return nil }
            let status = str.prefix(2).trimmingCharacters(in: .whitespaces)
            let filePath = String(str.dropFirst(3))
            return Repository.ChangedFile(status: status, path: filePath)
        }

        return (branch.isEmpty ? "main" : branch, files)
    }

    static func diff(at path: String) async -> String {
        let staged = await run("git", args: ["-C", path, "diff", "--cached"])
        let unstaged = await run("git", args: ["-C", path, "diff"])
        let untracked = await run("git", args: ["-C", path, "ls-files", "--others", "--exclude-standard"])

        var result = ""
        if !staged.isEmpty { result += staged }
        if !unstaged.isEmpty { result += "\n" + unstaged }
        if !untracked.isEmpty { result += "\nUntracked files:\n" + untracked }

        if result.count > 8000 {
            result = String(result.prefix(8000)) + "\n... (truncated)"
        }
        return result
    }

    static func commit(at path: String, message: String) async -> Result<Void, GitError> {
        let addOutput = await run("git", args: ["-C", path, "add", "-A"], includeStderr: true)
        if addOutput.contains("fatal:") {
            return .failure(GitError(message: "Failed to stage: \(addOutput)"))
        }

        let output = await run("git", args: ["-C", path, "commit", "-m", message], includeStderr: true)
        if output.contains("fatal:") || output.contains("error:") {
            return .failure(GitError(message: output.trimmingCharacters(in: .whitespacesAndNewlines)))
        }
        return .success(())
    }

    static func push(at path: String) async -> Result<Void, GitError> {
        let output = await run("git", args: ["-C", path, "push"], includeStderr: true)
        if output.contains("fatal:") || output.contains("error:") {
            let branch = await run("git", args: ["-C", path, "rev-parse", "--abbrev-ref", "HEAD"])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let retryOutput = await run("git", args: ["-C", path, "push", "-u", "origin", branch], includeStderr: true)
            if retryOutput.contains("fatal:") || retryOutput.contains("error:") {
                return .failure(GitError(message: retryOutput.trimmingCharacters(in: .whitespacesAndNewlines)))
            }
        }
        return .success(())
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
                process.waitUntilExit()

                var output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                if includeStderr {
                    let errOutput = String(data: errorPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                    if !errOutput.isEmpty { output += "\n" + errOutput }
                }
                return output
            } catch {
                return ""
            }
        }.value
    }
}
