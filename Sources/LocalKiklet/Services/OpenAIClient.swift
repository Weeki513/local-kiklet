import Foundation

enum OpenAIClientError: LocalizedError {
    case missingAPIKey
    case invalidResponse
    case apiError(String)

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            "API-ключ OpenAI не задан."
        case .invalidResponse:
            "Не удалось прочитать ответ OpenAI."
        case .apiError(let message):
            "OpenAI API: \(message)"
        }
    }
}

final class OpenAIClient {
    private let session: URLSession
    private let logger: AppLogger
    private let baseURL = URL(string: "https://api.openai.com/v1")!

    init(session: URLSession = .shared, logger: AppLogger = .shared) {
        self.session = session
        self.logger = logger
    }

    func runAction(input: String, instruction: String, apiKey: String) async throws -> String {
        guard !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw OpenAIClientError.missingAPIKey
        }

        let requestBody = ChatRequest(
            model: "gpt-4o-mini",
            temperature: 0.2,
            messages: [
                .init(role: "system", content: instruction),
                .init(role: "user", content: input)
            ]
        )

        var request = URLRequest(url: baseURL.appendingPathComponent("chat/completions"))
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONEncoder().encode(requestBody)

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw OpenAIClientError.invalidResponse
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            if let apiError = try? JSONDecoder().decode(OpenAIErrorEnvelope.self, from: data) {
                throw OpenAIClientError.apiError(apiError.error.message)
            }
            throw OpenAIClientError.apiError("HTTP \(httpResponse.statusCode)")
        }

        let payload = try JSONDecoder().decode(ChatResponse.self, from: data)
        guard let text = payload.choices.first?.message.resolvedContent,
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw OpenAIClientError.invalidResponse
        }

        logger.info("OpenAI action completed")
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func verifyKey(_ apiKey: String) async -> Result<Void, Error> {
        guard !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return .failure(OpenAIClientError.missingAPIKey)
        }

        var request = URLRequest(url: baseURL.appendingPathComponent("models"))
        request.httpMethod = "GET"
        request.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        do {
            let (_, response) = try await session.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                return .failure(OpenAIClientError.invalidResponse)
            }
            guard (200..<300).contains(httpResponse.statusCode) else {
                return .failure(OpenAIClientError.apiError("HTTP \(httpResponse.statusCode)"))
            }
            return .success(())
        } catch {
            return .failure(error)
        }
    }
}

private struct ChatRequest: Encodable {
    struct Message: Encodable {
        let role: String
        let content: String
    }

    let model: String
    let temperature: Double
    let messages: [Message]
}

private struct ChatResponse: Decodable {
    struct Choice: Decodable {
        struct Message: Decodable {
            let content: StringOrArray

            var resolvedContent: String {
                switch content {
                case .string(let text):
                    text
                case .array(let chunks):
                    chunks.map(\.text).joined(separator: "\n")
                }
            }
        }

        let message: Message
    }

    let choices: [Choice]
}

private struct OpenAIErrorEnvelope: Decodable {
    struct APIError: Decodable {
        let message: String
    }

    let error: APIError
}

private enum StringOrArray: Decodable {
    struct Chunk: Decodable {
        let text: String

        private enum CodingKeys: String, CodingKey {
            case text
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            text = try container.decodeIfPresent(String.self, forKey: .text) ?? ""
        }
    }

    case string(String)
    case array([Chunk])

    init(from decoder: Decoder) throws {
        let singleValueContainer = try decoder.singleValueContainer()
        if let text = try? singleValueContainer.decode(String.self) {
            self = .string(text)
            return
        }
        if let chunks = try? singleValueContainer.decode([Chunk].self) {
            self = .array(chunks)
            return
        }
        self = .string("")
    }
}
