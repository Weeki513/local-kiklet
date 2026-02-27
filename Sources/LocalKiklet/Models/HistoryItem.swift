import Foundation

struct HistoryItem: Identifiable, Codable, Hashable {
    let id: UUID
    let createdAt: Date
    let actionName: String
    let transcription: String
    let resultText: String
    let metadata: [String: String]

    init(
        id: UUID = UUID(),
        createdAt: Date = Date(),
        actionName: String,
        transcription: String,
        resultText: String,
        metadata: [String: String] = [:]
    ) {
        self.id = id
        self.createdAt = createdAt
        self.actionName = actionName
        self.transcription = transcription
        self.resultText = resultText
        self.metadata = metadata
    }
}
