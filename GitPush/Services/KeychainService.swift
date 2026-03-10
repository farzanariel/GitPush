import Foundation

/// Stores API keys in a local file with restricted permissions (owner read/write only).
/// Uses Application Support directory — no Keychain prompts, no code signing required.
struct KeychainService {
    private static var storageURL: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("GitPush", isDirectory: true)

        if !FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            // Restrict directory to owner only
            try? FileManager.default.setAttributes(
                [.posixPermissions: 0o700],
                ofItemAtPath: dir.path
            )
        }

        return dir.appendingPathComponent("keys.json")
    }

    private static func loadAll() -> [String: String] {
        guard let data = try? Data(contentsOf: storageURL),
              let dict = try? JSONDecoder().decode([String: String].self, from: data) else {
            return [:]
        }
        return dict
    }

    private static func saveAll(_ dict: [String: String]) {
        guard let data = try? JSONEncoder().encode(dict) else { return }
        try? data.write(to: storageURL, options: .atomic)
        // Restrict file to owner read/write only
        try? FileManager.default.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: storageURL.path
        )
    }

    static func save(key: String, value: String) -> Bool {
        var dict = loadAll()
        if value.isEmpty {
            dict.removeValue(forKey: key)
        } else {
            dict[key] = value
        }
        saveAll(dict)
        return true
    }

    static func load(key: String) -> String? {
        loadAll()[key]
    }

    static func delete(key: String) {
        var dict = loadAll()
        dict.removeValue(forKey: key)
        saveAll(dict)
    }
}
