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
    var branch: String
    var changedFileCount: Int
    var changedFiles: [ChangedFile]
    var unpushedCount: Int = 0
    var operation: RepoOperation = .idle
    var commitMessage: String = ""

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
