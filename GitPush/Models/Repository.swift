import Foundation

enum RepoOperation: Equatable {
    case idle
    case committing
    case pushing
    case success
    case error(String)

    var isInProgress: Bool {
        switch self {
        case .committing, .pushing: return true
        default: return false
        }
    }
}

struct Repository: Identifiable, Equatable {
    let id: String
    let path: String
    let name: String
    var location: RepositoryLocation = .local
    var branch: String
    var changedFileCount: Int
    var changedFiles: [ChangedFile]
    var unpushedCount: Int = 0
    var operation: RepoOperation = .idle
    var commitMessage: String = ""

    var displayPath: String {
        switch location {
        case .local:
            return path
        case .remote(let host):
            return "\(host):\(path)"
        }
    }

    var remoteHost: String? {
        switch location {
        case .local:
            return nil
        case .remote(let host):
            return host
        }
    }

    struct ChangedFile: Identifiable, Equatable {
        let id = UUID()
        let status: String // "M", "A", "D", "??"
        let path: String

        var statusLabel: String {
            switch status {
            case "M": return "Modified"
            case "A": return "Added"
            case "D": return "Deleted"
            case "??": return "Untracked"
            case "R": return "Renamed"
            default: return status
            }
        }

        var statusColor: String {
            switch status {
            case "M": return "orange"
            case "A": return "green"
            case "D": return "red"
            case "??": return "blue"
            default: return "secondary"
            }
        }
    }
}

enum RepositoryLocation: Equatable {
    case local
    case remote(host: String)
}

struct RemoteProjectRoot: Identifiable, Equatable {
    let host: String
    let path: String

    var id: String { "\(host):\(path)" }
    var displayValue: String { id }

    static func parseLines(_ text: String) -> [RemoteProjectRoot] {
        text
            .split(separator: "\n")
            .compactMap { parse(String($0)) }
    }

    static func parse(_ value: String) -> RemoteProjectRoot? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let separator = trimmed.firstIndex(of: ":") else {
            return nil
        }

        let host = String(trimmed[..<separator]).trimmingCharacters(in: .whitespacesAndNewlines)
        let pathStart = trimmed.index(after: separator)
        let path = String(trimmed[pathStart...]).trimmingCharacters(in: .whitespacesAndNewlines)

        guard !host.isEmpty, path.hasPrefix("/") || path.hasPrefix("~") else {
            return nil
        }

        return RemoteProjectRoot(host: host, path: path)
    }
}
