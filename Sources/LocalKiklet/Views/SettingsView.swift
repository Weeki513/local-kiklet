import SwiftUI

struct SettingsView: View {
    @ObservedObject var model: AppViewModel

    @State private var editingAction: TextAction?

    private let languages: [(String, String)] = [
        ("auto", "Auto"),
        ("ru", "Русский"),
        ("en", "English"),
        ("de", "Deutsch"),
        ("fr", "Français"),
        ("es", "Español")
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                permissionSection
                startupSection
                hotkeysSection
                transcriptionSection
                outputSection
                actionsSection
                apiKeySection
                diagnosticsSection
            }
            .padding(20)
        }
        .frame(minWidth: 780, minHeight: 680)
        .sheet(item: $editingAction) { action in
            ActionEditorView(action: action) {
                model.upsertAction($0)
            }
        }
    }

    private var permissionSection: some View {
        GroupBox("Разрешения") {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(PermissionKind.allCases) { kind in
                    HStack {
                        Text(kind.title)
                        Spacer()
                        Text(model.permissionManager.status(for: kind) ? "Выдано" : "Нет")
                            .foregroundStyle(model.permissionManager.status(for: kind) ? .green : .red)
                        Button("Запросить") {
                            model.requestPermission(kind)
                        }
                        Button("Открыть настройки") {
                            model.openPermissionSettings(kind)
                        }
                    }
                }

                Button("Открыть онбординг") {
                    model.openOnboarding()
                }

                HStack {
                    Button("Проверить разрешения") {
                        model.checkPermissions()
                        model.restartHotkeys()
                    }
                    Button("Запросить все") {
                        model.requestAllMissingPermissions()
                    }
                    Button("Скопировать путь app") {
                        model.copyCurrentAppPath()
                    }
                    Button("Показать app в Finder") {
                        model.revealCurrentAppInFinder()
                    }
                }

                if let permissionsStatus = model.permissionsStatusMessage {
                    Text(permissionsStatus)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 4)
        }
    }

    private var startupSection: some View {
        GroupBox("Запуск") {
            VStack(alignment: .leading, spacing: 8) {
                Toggle(
                    "Автозапуск со стартом macOS",
                    isOn: Binding(
                        get: { model.launchAtLoginEnabled },
                        set: { model.setLaunchAtLogin($0) }
                    )
                )

                if let startupStatus = model.launchAtLoginStatusMessage {
                    Text(startupStatus)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Button("Обновить статус") {
                    model.refreshLaunchAtLoginState()
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 4)
        }
    }

    private var hotkeysSection: some View {
        GroupBox("Горячие клавиши") {
            VStack(alignment: .leading, spacing: 12) {
                HotkeyCaptureView(
                    hotkey: Binding(
                        get: { model.settingsStore.settings.holdHotkey },
                        set: { model.settingsStore.settings.holdHotkey = $0 }
                    ),
                    title: "Hold-to-record"
                )

                HotkeyCaptureView(
                    hotkey: Binding(
                        get: { model.settingsStore.settings.toggleHotkey },
                        set: { model.settingsStore.settings.toggleHotkey = $0 }
                    ),
                    title: "Toggle record"
                )

                Text("Поддерживаются обычные комбинации и модификатор-only (например, только ⌥).")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if let hotkeyHint = model.hotkeyRequirementsMessage {
                    Text(hotkeyHint)
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 4)
        }
    }

    private var transcriptionSection: some View {
        GroupBox("Распознавание") {
            VStack(alignment: .leading, spacing: 10) {
                Picker("Язык", selection: Binding(
                    get: { model.settingsStore.settings.recognitionLanguage },
                    set: { model.settingsStore.settings.recognitionLanguage = $0 }
                )) {
                    ForEach(languages, id: \.0) { code, title in
                        Text(title).tag(code)
                    }
                }

                Picker("Качество", selection: Binding(
                    get: { model.settingsStore.settings.transcriptionQuality },
                    set: { model.settingsStore.settings.transcriptionQuality = $0 }
                )) {
                    ForEach(TranscriptionQuality.allCases) { quality in
                        Text(quality.title).tag(quality)
                    }
                }

                TextField("Путь к whisper-cli", text: Binding(
                    get: { model.settingsStore.settings.whisperCLIPath },
                    set: { model.settingsStore.settings.whisperCLIPath = $0 }
                ))

                TextField("Путь к fast модели", text: Binding(
                    get: { model.settingsStore.settings.fastModelPath },
                    set: { model.settingsStore.settings.fastModelPath = $0 }
                ))

                TextField("Путь к accurate модели", text: Binding(
                    get: { model.settingsStore.settings.accurateModelPath },
                    set: { model.settingsStore.settings.accurateModelPath = $0 }
                ))

                VStack(alignment: .leading, spacing: 6) {
                    Text(model.localEngineStatusMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    HStack {
                        Button(model.isInstallingLocalEngine ? "Устанавливаю..." : "Установить локальный Whisper") {
                            model.installLocalEngine()
                        }
                        .disabled(model.isInstallingLocalEngine)

                        Button("Проверить статус") {
                            model.refreshLocalEngineStatus()
                        }
                        .disabled(model.isInstallingLocalEngine)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 4)
        }
    }

    private var outputSection: some View {
        GroupBox("Вставка/буфер") {
            VStack(alignment: .leading, spacing: 8) {
                Picker("Режим", selection: Binding(
                    get: { model.settingsStore.settings.outputMode },
                    set: { model.settingsStore.settings.outputMode = $0 }
                )) {
                    ForEach(OutputMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 4)
        }
    }

    private var actionsSection: some View {
        GroupBox("Действия") {
            VStack(alignment: .leading, spacing: 10) {
                Picker("Действие по умолчанию", selection: Binding(
                    get: { model.settingsStore.settings.defaultActionID },
                    set: { model.updateSelectedAction($0) }
                )) {
                    ForEach(model.actions) { action in
                        Text(action.name).tag(action.id)
                    }
                }

                List(model.actions) { action in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(action.name)
                            Text(action.description)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        if action.isBuiltIn {
                            Text("Built-in")
                                .font(.caption2)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(.quaternary)
                                .clipShape(Capsule())

                            if model.isBuiltInActionCustomized(action.id) {
                                Text("Изменено")
                                    .font(.caption2)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(.orange.opacity(0.18))
                                    .clipShape(Capsule())
                            }
                        }
                        Button("Дубль") {
                            model.duplicateAction(action.id)
                        }
                        .buttonStyle(.borderless)

                        Button("Изм.") {
                            editingAction = action
                        }
                        .buttonStyle(.borderless)

                        if action.isBuiltIn {
                            if model.isBuiltInActionCustomized(action.id) {
                                Button("Сброс") {
                                    model.resetBuiltInAction(action.id)
                                }
                                .buttonStyle(.borderless)
                            }
                        } else {
                            Button("Удалить") {
                                model.removeAction(action.id)
                            }
                            .buttonStyle(.borderless)
                            .foregroundStyle(.red)
                        }
                    }
                }
                .frame(height: 230)

                HStack {
                    Button("Добавить кастомное") {
                        editingAction = TextAction(
                            name: "Новое действие",
                            description: "Описание",
                            engine: .openAI,
                            instruction: "Rewrite the text to improve clarity.",
                            isBuiltIn: false
                        )
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 4)
        }
    }

    private var apiKeySection: some View {
        GroupBox("OpenAI") {
            VStack(alignment: .leading, spacing: 8) {
                SecureField("API key", text: $model.apiKeyFieldValue)
                HStack {
                    Button("Сохранить") {
                        model.saveAPIKey()
                    }
                    Button("Проверить ключ") {
                        model.verifyAPIKey()
                    }
                    if let message = model.apiKeyStatusMessage {
                        Text(message)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                if !model.hasAPIKey {
                    Text("Без ключа доступны запись и локальная транскрибация; OpenAI-действия покажут ошибку.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 4)
        }
    }

    private var diagnosticsSection: some View {
        GroupBox("Диагностика") {
            VStack(alignment: .leading, spacing: 8) {
                Text("Bundle ID: \(model.bundleIdentifier)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("Путь app: \(model.currentAppPath)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("Лог-файл: \(AppPaths.logFile.path)")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                HStack {
                    Button("Скопировать путь app") {
                        model.copyCurrentAppPath()
                    }
                    Button("Показать app в Finder") {
                        model.revealCurrentAppInFinder()
                    }
                    Button("Экспорт логов") {
                        model.exportLogs()
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 4)
        }
    }
}
