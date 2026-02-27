import Foundation

struct ActionOutput {
    let text: String
    let metadata: [String: String]
}

final class ActionRunner: @unchecked Sendable {
    private let openAI: OpenAIClient
    private let keychain: KeychainStore

    init(openAI: OpenAIClient = OpenAIClient(), keychain: KeychainStore = KeychainStore()) {
        self.openAI = openAI
        self.keychain = keychain
    }

    func run(action: TextAction, text: String) async throws -> ActionOutput {
        if action.engine == .none {
            return ActionOutput(text: text, metadata: [:])
        }

        guard let apiKey = keychain.readAPIKey(), !apiKey.isEmpty else {
            throw OpenAIClientError.missingAPIKey
        }

        let resultText = try await openAI.runAction(input: text, instruction: action.instruction, apiKey: apiKey)
        var metadata: [String: String] = [:]
        if let targetLanguage = action.targetLanguage {
            metadata["language"] = targetLanguage
        }
        return ActionOutput(text: resultText, metadata: metadata)
    }

    func verifyAPIKey(_ value: String) async -> Result<Void, Error> {
        await openAI.verifyKey(value)
    }
}
