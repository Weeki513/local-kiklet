import SwiftUI

struct ActionEditorView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var draft: TextAction
    let onSave: (TextAction) -> Void

    init(action: TextAction, onSave: @escaping (TextAction) -> Void) {
        _draft = State(initialValue: action)
        self.onSave = onSave
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Действие")
                .font(.title3)
                .bold()

            Form {
                TextField("Название", text: $draft.name)
                TextField("Описание", text: $draft.description)
                Picker("Тип", selection: $draft.engine) {
                    Text("Без обработки").tag(TextAction.Engine.none)
                    Text("OpenAI").tag(TextAction.Engine.openAI)
                }

                TextField("Формат входа", text: $draft.inputFormat)
                TextField("Целевой язык (опц.)", text: Binding(
                    get: { draft.targetLanguage ?? "" },
                    set: { draft.targetLanguage = $0.isEmpty ? nil : $0 }
                ))

                if draft.engine == .openAI {
                    TextEditor(text: $draft.instruction)
                        .frame(height: 120)
                        .font(.system(.body, design: .monospaced))
                }
            }

            HStack {
                Spacer()
                Button("Отмена") {
                    dismiss()
                }
                Button("Сохранить") {
                    onSave(draft)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(draft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(16)
        .frame(minWidth: 520, minHeight: 430)
    }
}
