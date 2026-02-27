import Foundation

struct TextAction: Identifiable, Codable, Hashable {
    enum Engine: String, Codable, CaseIterable {
        case none
        case openAI
    }

    var id: String
    var name: String
    var description: String
    var engine: Engine
    var instruction: String
    var targetLanguage: String?
    var inputFormat: String
    var metadataKeys: [String]
    var isBuiltIn: Bool

    init(
        id: String = UUID().uuidString,
        name: String,
        description: String,
        engine: Engine,
        instruction: String,
        targetLanguage: String? = nil,
        inputFormat: String = "plain-text",
        metadataKeys: [String] = [],
        isBuiltIn: Bool = false
    ) {
        self.id = id
        self.name = name
        self.description = description
        self.engine = engine
        self.instruction = instruction
        self.targetLanguage = targetLanguage
        self.inputFormat = inputFormat
        self.metadataKeys = metadataKeys
        self.isBuiltIn = isBuiltIn
    }
}

enum BuiltInActions {
    static let passthroughID = "builtin_passthrough"
    private static let sameLanguageRuleEN = "Return the final answer strictly in the same language as the input text."
    private static let sameLanguageRuleRU = "Верни итоговый ответ строго на том же языке, что и исходный текст."

    static let all: [TextAction] = [
        TextAction(
            id: passthroughID,
            name: "Без обработки (только транскрипция)",
            description: "Вернуть локальную транскрипцию без изменений.",
            engine: .none,
            instruction: sameLanguageRuleRU,
            isBuiltIn: true
        ),
        TextAction(
            id: "builtin_translate_en",
            name: "Перевести на английский",
            description: "Перевести текст на естественный английский.",
            engine: .openAI,
            instruction: "Translate the text to natural English. Keep the original meaning and preserve names. By default answer in the input language, but this action is a translation exception: return the final answer in English only.",
            targetLanguage: "en",
            metadataKeys: ["language"],
            isBuiltIn: true
        ),
        TextAction(
            id: "builtin_translate_ru",
            name: "Перевести на русский",
            description: "Перевести текст на русский язык.",
            engine: .openAI,
            instruction: "Переведи текст на естественный русский язык без потери смысла. По умолчанию отвечай на языке исходного текста, но это действие — исключение для перевода: верни итоговый ответ только на русском языке.",
            targetLanguage: "ru",
            metadataKeys: ["language"],
            isBuiltIn: true
        ),
        TextAction(
            id: "builtin_formal",
            name: "Сделать формально-деловым стилем",
            description: "Переписать текст в формально-деловом стиле.",
            engine: .openAI,
            instruction: "Rewrite the text in a concise formal business tone. \(sameLanguageRuleEN)",
            metadataKeys: ["tone"],
            isBuiltIn: true
        ),
        TextAction(
            id: "builtin_friendly",
            name: "Сделать проще/дружелюбнее",
            description: "Упростить текст и сделать дружелюбнее.",
            engine: .openAI,
            instruction: "Rewrite the text in a friendly, simple, and clear style. \(sameLanguageRuleEN)",
            metadataKeys: ["tone"],
            isBuiltIn: true
        ),
        TextAction(
            id: "builtin_compress",
            name: "Сжать в 1-2 предложения",
            description: "Сократить текст в короткое резюме.",
            engine: .openAI,
            instruction: "Compress the text into 1-2 sentences while preserving the key message. \(sameLanguageRuleEN)",
            metadataKeys: ["summary_length"],
            isBuiltIn: true
        ),
        TextAction(
            id: "builtin_todo",
            name: "Список задач (to-do)",
            description: "Преобразовать текст в список задач.",
            engine: .openAI,
            instruction: "Extract actionable tasks from the text and return a concise bullet list. \(sameLanguageRuleEN)",
            metadataKeys: ["task_count"],
            isBuiltIn: true
        ),
        TextAction(
            id: "builtin_summary",
            name: "Краткое резюме",
            description: "Сделать краткое резюме по сути.",
            engine: .openAI,
            instruction: "Summarize the text with key points in a short paragraph. \(sameLanguageRuleEN)",
            metadataKeys: ["language"],
            isBuiltIn: true
        )
    ]

    private static let byID: [String: TextAction] = {
        Dictionary(uniqueKeysWithValues: all.map { ($0.id, $0) })
    }()

    static func defaultAction(for id: String) -> TextAction? {
        byID[id]
    }

    static func isBuiltIn(id: String) -> Bool {
        byID[id] != nil
    }
}
