import Foundation

@MainActor
final class HistoryStore: ObservableObject {
    @Published private(set) var items: [HistoryItem] = []

    private let fileURL: URL
    private let logger: AppLogger

    init(fileURL: URL = AppPaths.historyFile, logger: AppLogger = .shared) {
        self.fileURL = fileURL
        self.logger = logger
        load()
    }

    func add(_ item: HistoryItem, limit: Int) {
        items.insert(item, at: 0)
        if items.count > limit {
            items = Array(items.prefix(limit))
        }
        save()
    }

    func remove(id: UUID) {
        items.removeAll { $0.id == id }
        save()
    }

    func clear() {
        items.removeAll()
        save()
    }

    private func save() {
        do {
            let data = try JSONEncoder.historyEncoder.encode(items)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            logger.error("Failed to save history: \(error.localizedDescription)")
        }
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL) else { return }
        do {
            items = try JSONDecoder.historyDecoder.decode([HistoryItem].self, from: data)
        } catch {
            logger.warn("Failed to read history: \(error.localizedDescription)")
        }
    }
}

private extension JSONEncoder {
    static var historyEncoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}

private extension JSONDecoder {
    static var historyDecoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
