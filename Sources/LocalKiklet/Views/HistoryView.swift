import SwiftUI

struct HistoryView: View {
    @ObservedObject var model: AppViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("История")
                    .font(.title3)
                    .bold()
                Spacer()
                Text("Всего: \(model.historyStore.items.count)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            List(model.historyStore.items) { item in
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(item.actionName)
                            .bold()
                        Spacer()
                        Text(Self.dateFormatter.string(from: item.createdAt))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Group {
                        Text("Транскрипция")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(item.transcription)
                            .textSelection(.enabled)

                        Text("Результат")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(item.resultText)
                            .textSelection(.enabled)
                    }

                    HStack {
                        Button("Скопировать транскрипцию") {
                            model.copyTranscription(item)
                        }
                        Button("Скопировать результат") {
                            model.copyResult(item)
                        }
                        Button("Повторить действие") {
                            model.rerunAction(on: item)
                        }
                        Button("Удалить") {
                            model.deleteHistoryItem(item)
                        }
                        .foregroundStyle(.red)
                    }
                    .font(.caption)
                }
                .padding(.vertical, 6)
            }
        }
        .padding(16)
        .frame(minWidth: 780, minHeight: 520)
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .medium
        return formatter
    }()
}
