import Foundation

enum AIProvider: String, CaseIterable {
    case claude = "Claude"
    case openai = "OpenAI"
}

struct AIService {
    private static let commitPrompt = """
    Generate a concise git commit message for the following diff. \
    The message should be a single line, max 72 characters, in imperative mood \
    (e.g., "Add feature" not "Added feature"). No quotes, no prefix like "feat:" unless it's a clear convention. \
    Just return the commit message, nothing else.

    Diff:
    """

    static func generateCommitMessage(diff: String, apiKey: String, provider: AIProvider) async throws -> String {
        switch provider {
        case .claude:
            return try await callClaude(diff: diff, apiKey: apiKey)
        case .openai:
            return try await callOpenAI(diff: diff, apiKey: apiKey)
        }
    }

    // MARK: - Claude

    private struct ClaudeRequest: Encodable {
        let model: String
        let max_tokens: Int
        let messages: [Message]
        struct Message: Encodable { let role: String; let content: String }
    }

    private struct ClaudeResponse: Decodable {
        let content: [ContentBlock]
        struct ContentBlock: Decodable { let text: String? }
    }

    private static func callClaude(diff: String, apiKey: String) async throws -> String {
        let url = URL(string: "https://api.anthropic.com/v1/messages")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.timeoutInterval = 30

        let body = ClaudeRequest(
            model: "claude-haiku-4-5-20251001",
            max_tokens: 100,
            messages: [.init(role: "user", content: commitPrompt + diff)]
        )
        request.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }

        let decoded = try JSONDecoder().decode(ClaudeResponse.self, from: data)
        return decoded.content.first?.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "update"
    }

    // MARK: - OpenAI

    private struct OpenAIRequest: Encodable {
        let model: String
        let max_tokens: Int
        let messages: [Message]
        struct Message: Encodable { let role: String; let content: String }
    }

    private struct OpenAIResponse: Decodable {
        let choices: [Choice]
        struct Choice: Decodable {
            let message: ResponseMessage
            struct ResponseMessage: Decodable { let content: String? }
        }
    }

    private static func callOpenAI(diff: String, apiKey: String) async throws -> String {
        let url = URL(string: "https://api.openai.com/v1/chat/completions")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "authorization")
        request.timeoutInterval = 30

        let body = OpenAIRequest(
            model: "gpt-4o-mini",
            max_tokens: 100,
            messages: [.init(role: "user", content: commitPrompt + diff)]
        )
        request.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }

        let decoded = try JSONDecoder().decode(OpenAIResponse.self, from: data)
        return decoded.choices.first?.message.content?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "update"
    }
}
