import AppKit
import Combine
import Foundation
import UniformTypeIdentifiers

@MainActor
final class AppViewModel: ObservableObject {
    @Published var workflowState: WorkflowState = .idle
    @Published var statusMessage: String = "Готово"
    @Published var lastErrorMessage: String?
    @Published var showOnboarding: Bool
    @Published var apiKeyFieldValue: String = ""
    @Published var apiKeyStatusMessage: String?
    @Published private(set) var hasStoredAPIKey: Bool = false
    @Published var localEngineStatusMessage: String = "Проверяю локальный Whisper..."
    @Published var isInstallingLocalEngine: Bool = false
    @Published var launchAtLoginEnabled: Bool = false
    @Published var launchAtLoginStatusMessage: String?
    @Published var permissionsStatusMessage: String?
    @Published var runtimeStatusMessage: String?

    let settingsStore: SettingsStore
    let historyStore: HistoryStore
    let permissionManager: PermissionManager

    private let logger: AppLogger
    private let recorder: AudioRecorder
    private let transcriber: WhisperTranscriber
    private let injector: TextInjector
    private let actionRunner: ActionRunner
    private let keychain: KeychainStore
    private let notifier: Notifier
    private let whisperInstaller: LocalWhisperInstaller
    private let launchAtLoginManager: LaunchAtLoginManager
    private let cursorHUD: CursorStatusHUD
    private var hotkeyMonitor: HotkeyMonitor
    private var workflowTask: Task<Void, Never>?
    private var cancellables: Set<AnyCancellable> = []

    init(
        settingsStore: SettingsStore = SettingsStore(),
        historyStore: HistoryStore = HistoryStore(),
        permissionManager: PermissionManager = PermissionManager(),
        logger: AppLogger = .shared,
        recorder: AudioRecorder = AudioRecorder(),
        transcriber: WhisperTranscriber = WhisperTranscriber(),
        injector: TextInjector = TextInjector(),
        actionRunner: ActionRunner = ActionRunner(),
        keychain: KeychainStore = KeychainStore(),
        notifier: Notifier = Notifier(),
        whisperInstaller: LocalWhisperInstaller = LocalWhisperInstaller(),
        launchAtLoginManager: LaunchAtLoginManager = LaunchAtLoginManager(),
        cursorHUD: CursorStatusHUD = CursorStatusHUD()
    ) {
        self.settingsStore = settingsStore
        self.historyStore = historyStore
        self.permissionManager = permissionManager
        self.logger = logger
        self.recorder = recorder
        self.transcriber = transcriber
        self.injector = injector
        self.actionRunner = actionRunner
        self.keychain = keychain
        self.notifier = notifier
        self.whisperInstaller = whisperInstaller
        self.launchAtLoginManager = launchAtLoginManager
        self.cursorHUD = cursorHUD
        self.hotkeyMonitor = HotkeyMonitor(
            holdHotkey: settingsStore.settings.holdHotkey,
            toggleHotkey: settingsStore.settings.toggleHotkey
        )

        self.showOnboarding = !settingsStore.settings.onboardingCompleted
        let storedAPIKey = keychain.readAPIKey(allowInteraction: false)
        self.apiKeyFieldValue = storedAPIKey ?? ""
        self.hasStoredAPIKey = !(storedAPIKey?.isEmpty ?? true)

        configureBindings()
        configureHotkeys()
        notifier.requestAuthorization()
        logger.info("App launch pid=\(ProcessInfo.processInfo.processIdentifier) bundle=\(bundleIdentifier) path=\(currentAppPath)")

        Task {
            try? await Task.sleep(for: .seconds(0.8))
            await permissionManager.requestInputMonitoringIfNeeded()
            await MainActor.run {
                self.checkPermissions()
            }
        }
        updateRuntimeStatus()
        checkPermissions()
        refreshLaunchAtLoginState()
        refreshLocalEngineStatus(autoInstall: true)
    }

    var actions: [TextAction] {
        settingsStore.settings.allActions
    }

    var selectedAction: TextAction {
        settingsStore.settings.selectedAction
    }

    var hasAPIKey: Bool {
        hasStoredAPIKey
    }

    var currentAppPath: String {
        Bundle.main.bundleURL.path
    }

    var bundleIdentifier: String {
        Bundle.main.bundleIdentifier ?? "unknown"
    }

    var hotkeyRequirementsMessage: String? {
        let settings = settingsStore.settings
        if (settings.holdHotkey.isModifierOnly || settings.toggleHotkey.isModifierOnly),
           !permissionManager.inputMonitoringGranted {
            return "Для modifier-only горячих клавиш нужен Input Monitoring. После выдачи разрешения нажмите «Проверить разрешения»."
        }
        return nil
    }

    func requestPermission(_ kind: PermissionKind) {
        Task {
            await permissionManager.request(kind)
            await MainActor.run {
                self.checkPermissions()
                self.restartHotkeys()
            }
        }
    }

    func openPermissionSettings(_ kind: PermissionKind) {
        permissionManager.openSettings(for: kind)
    }

    func requestAllMissingPermissions() {
        Task {
            if !permissionManager.microphoneGranted {
                await permissionManager.request(.microphone)
            }
            if !permissionManager.accessibilityGranted {
                await permissionManager.request(.accessibility)
            }
            if !permissionManager.inputMonitoringGranted {
                await permissionManager.request(.inputMonitoring)
            }
            await MainActor.run {
                self.checkPermissions()
                self.restartHotkeys()
            }
        }
    }

    func checkPermissions() {
        permissionManager.refreshStatuses()
        let missing = PermissionKind.allCases.filter { !permissionManager.status(for: $0) }
        var parts: [String] = []

        if missing.isEmpty {
            parts.append("Все ключевые разрешения выданы")
        } else {
            let names = missing.map(\.title).joined(separator: ", ")
            parts.append("Не выданы: \(names)")
        }

        if let hotkeyRequirementsMessage {
            parts.append(hotkeyRequirementsMessage)
        }
        if let runtimeStatusMessage {
            parts.append(runtimeStatusMessage)
        }
        permissionsStatusMessage = parts.joined(separator: " | ")
    }

    func restartHotkeys() {
        hotkeyMonitor.stop()
        do {
            try hotkeyMonitor.start()
            if permissionManager.inputMonitoringGranted {
                lastErrorMessage = nil
            }
        } catch {
            lastErrorMessage = error.localizedDescription
            logger.warn("Restart hotkeys failed: \(error.localizedDescription)")
        }
    }

    func copyCurrentAppPath() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(currentAppPath, forType: .string)
        statusMessage = "Путь приложения скопирован"
    }

    func revealCurrentAppInFinder() {
        NSWorkspace.shared.activateFileViewerSelecting([Bundle.main.bundleURL])
        statusMessage = "Показан текущий .app в Finder"
    }

    func completeOnboarding() {
        settingsStore.settings.onboardingCompleted = true
        showOnboarding = false
    }

    func openOnboarding() {
        showOnboarding = true
    }

    func updateSelectedAction(_ actionID: String) {
        settingsStore.settings.defaultActionID = actionID
    }

    func refreshLaunchAtLoginState() {
        let state = launchAtLoginManager.currentState()
        launchAtLoginEnabled = state.isOnForToggle
        launchAtLoginStatusMessage = state.hint
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            try launchAtLoginManager.setEnabled(enabled)
            refreshLaunchAtLoginState()
            statusMessage = enabled ? "Автозапуск включён" : "Автозапуск отключён"
        } catch {
            refreshLaunchAtLoginState()
            launchAtLoginStatusMessage = error.localizedDescription
            lastErrorMessage = error.localizedDescription
            logger.warn("Launch at login update failed: \(error.localizedDescription)")
        }
    }

    func refreshLocalEngineStatus(autoInstall: Bool = false) {
        let status = whisperInstaller.status(for: settingsStore.settings)
        if status.isReady {
            localEngineStatusMessage = "Локальный Whisper готов"
            return
        }

        localEngineStatusMessage = "Отсутствует: \(status.missingItemsDescription)"
        if autoInstall {
            installLocalEngine(automatic: true)
        }
    }

    func installLocalEngine(automatic: Bool = false) {
        guard !isInstallingLocalEngine else { return }
        isInstallingLocalEngine = true
        localEngineStatusMessage = automatic
            ? "Автонастройка локального Whisper..."
            : "Устанавливаю локальный Whisper..."

        let snapshot = settingsStore.settings
        Task {
            do {
                localEngineStatusMessage = "Проверяю окружение и устанавливаю whisper-cpp..."
                let updated = try await whisperInstaller.ensureInstalled(
                    settings: snapshot,
                    allowBrewInstall: true
                )

                settingsStore.settings.whisperCLIPath = updated.whisperCLIPath
                settingsStore.settings.fastModelPath = updated.fastModelPath
                settingsStore.settings.accurateModelPath = updated.accurateModelPath

                isInstallingLocalEngine = false
                localEngineStatusMessage = "Локальный Whisper готов"
                if !automatic {
                    statusMessage = "Локальный движок установлен"
                    cursorHUD.showTransient(text: "Локальный Whisper готов", color: .systemGreen)
                }
            } catch {
                isInstallingLocalEngine = false
                localEngineStatusMessage = error.localizedDescription
                lastErrorMessage = error.localizedDescription
                logger.warn("Local whisper setup failed: \(error.localizedDescription)")
            }
        }
    }

    func upsertAction(_ action: TextAction) {
        settingsStore.upsertCustomAction(action)
    }

    func removeAction(_ actionID: String) {
        settingsStore.removeCustomAction(id: actionID)
    }

    func isBuiltInActionCustomized(_ actionID: String) -> Bool {
        settingsStore.settings.customActions.contains { $0.id == actionID && BuiltInActions.isBuiltIn(id: actionID) }
    }

    func resetBuiltInAction(_ actionID: String) {
        settingsStore.resetBuiltInAction(id: actionID)
        statusMessage = "Предустановленное действие сброшено"
    }

    func duplicateAction(_ actionID: String) {
        settingsStore.duplicateAction(id: actionID)
    }

    func startRecordingFromUI() {
        if workflowState == .recording {
            stopRecordingAndProcess()
        } else {
            startRecording()
        }
    }

    func cancelCurrentWorkflow() {
        transcriber.cancel()
        workflowTask?.cancel()
        workflowTask = nil
        workflowState = .idle
        statusMessage = "Операция отменена"
        cursorHUD.showTransient(text: "Операция отменена", color: .systemOrange)
    }

    func saveAPIKey() {
        let trimmed = apiKeyFieldValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            if keychain.deleteAPIKey() {
                hasStoredAPIKey = false
                apiKeyStatusMessage = "Ключ удалён"
            } else {
                apiKeyStatusMessage = "Не удалось удалить ключ"
            }
            return
        }
        if keychain.saveAPIKey(trimmed) {
            hasStoredAPIKey = true
            apiKeyStatusMessage = "Ключ сохранён"
        } else {
            apiKeyStatusMessage = "Не удалось сохранить ключ"
        }
    }

    func verifyAPIKey() {
        let trimmed = apiKeyFieldValue.trimmingCharacters(in: .whitespacesAndNewlines)
        Task {
            let result = await actionRunner.verifyAPIKey(trimmed)
            await MainActor.run {
                switch result {
                case .success:
                    self.apiKeyStatusMessage = "Ключ валиден"
                case .failure(let error):
                    self.apiKeyStatusMessage = "Проверка не прошла: \(error.localizedDescription)"
                }
            }
        }
    }

    func exportLogs() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "localkiklet.log"
        panel.allowedContentTypes = [.log]
        if panel.runModal() == .OK, let destination = panel.url {
            do {
                try logger.exportLogs(to: destination)
                statusMessage = "Логи экспортированы"
            } catch {
                lastErrorMessage = "Не удалось экспортировать логи: \(error.localizedDescription)"
            }
        }
    }

    func copyTranscription(_ item: HistoryItem) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(item.transcription, forType: .string)
        statusMessage = "Транскрипция скопирована"
    }

    func copyResult(_ item: HistoryItem) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(item.resultText, forType: .string)
        statusMessage = "Результат скопирован"
    }

    func rerunAction(on item: HistoryItem) {
        let action = selectedAction
        workflowTask?.cancel()
        workflowTask = Task {
            await runActionPipeline(sourceText: item.transcription, action: action, actionNameOverride: action.name)
        }
    }

    func deleteHistoryItem(_ item: HistoryItem) {
        historyStore.remove(id: item.id)
    }

    private func configureBindings() {
        settingsStore.$settings
            .sink { [weak self] settings in
                guard let self else { return }
                hotkeyMonitor.update(holdHotkey: settings.holdHotkey, toggleHotkey: settings.toggleHotkey)
            }
            .store(in: &cancellables)
    }

    private func updateRuntimeStatus() {
        let appPath = currentAppPath
        if appPath.contains("/AppTranslocation/") || appPath.hasPrefix("/Volumes/") {
            runtimeStatusMessage = "Приложение запущено не из /Applications. Текущий путь: \(appPath)"
        } else if !appPath.hasPrefix("/Applications/") {
            runtimeStatusMessage = "Рекомендуется запуск из /Applications. Текущий путь: \(appPath)"
        } else {
            runtimeStatusMessage = nil
        }
    }

    private func configureHotkeys() {
        hotkeyMonitor.onHoldStart = { [weak self] in
            Task { @MainActor [weak self] in
                self?.startRecording()
            }
        }
        hotkeyMonitor.onHoldStop = { [weak self] in
            Task { @MainActor [weak self] in
                self?.stopRecordingAndProcess()
            }
        }
        hotkeyMonitor.onTogglePressed = { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                if self.workflowState == .recording {
                    self.stopRecordingAndProcess()
                } else {
                    self.startRecording()
                }
            }
        }

        do {
            try hotkeyMonitor.start()
        } catch {
            lastErrorMessage = error.localizedDescription
            logger.error("Hotkey monitor failed: \(error.localizedDescription)")
            Task {
                await permissionManager.requestInputMonitoringIfNeeded()
            }
        }
    }

    private func startRecording() {
        guard workflowState == .idle else { return }
        permissionManager.refreshStatuses()
        guard permissionManager.microphoneGranted else {
            lastErrorMessage = "Нужен доступ к микрофону"
            statusMessage = "Нет доступа к микрофону"
            notifier.send(title: "Local Kiklet", body: "Разрешите доступ к микрофону в системных настройках")
            cursorHUD.showTransient(text: "Нет доступа к микрофону", color: .systemRed)
            return
        }

        do {
            try recorder.start()
            workflowState = .recording
            statusMessage = "Идёт запись"
            lastErrorMessage = nil
            cursorHUD.showPersistent(text: "Идёт запись", color: .systemRed)
        } catch {
            lastErrorMessage = error.localizedDescription
            statusMessage = "Ошибка записи"
            logger.error("Start recording failed: \(error.localizedDescription)")
            cursorHUD.showTransient(text: "Ошибка записи", color: .systemRed)
        }
    }

    private func stopRecordingAndProcess() {
        guard workflowState == .recording else { return }
        let audioURL: URL
        do {
            audioURL = try recorder.stop()
        } catch {
            lastErrorMessage = error.localizedDescription
            workflowState = .idle
            statusMessage = "Ошибка остановки записи"
            cursorHUD.showTransient(text: "Ошибка остановки записи", color: .systemRed)
            return
        }

        let settingsSnapshot = settingsStore.settings
        let action = settingsSnapshot.selectedAction

        workflowTask?.cancel()
        workflowTask = Task {
            await runRecordingPipeline(audioURL: audioURL, settings: settingsSnapshot, action: action)
        }
    }

    private func runRecordingPipeline(audioURL: URL, settings: AppSettings, action: TextAction) async {
        defer {
            try? FileManager.default.removeItem(at: audioURL)
        }

        workflowState = .transcribing
        statusMessage = "Транскрибирую..."
        cursorHUD.showPersistent(text: "Транскрибирую...", color: .systemOrange)

        do {
            let transcript = try await transcriber.transcribe(audioURL: audioURL, settings: settings)
            await runActionPipeline(sourceText: transcript, action: action, actionNameOverride: action.name)
        } catch is CancellationError {
            workflowState = .idle
            statusMessage = "Отменено"
            cursorHUD.showTransient(text: "Отменено", color: .systemOrange)
        } catch {
            workflowState = .idle
            lastErrorMessage = error.localizedDescription
            statusMessage = "Ошибка транскрибации"
            notifier.send(title: "Local Kiklet", body: error.localizedDescription)
            logger.error("Pipeline failed: \(error.localizedDescription)")
            cursorHUD.showTransient(text: "Ошибка транскрибации", color: .systemRed)
        }
    }

    private func runActionPipeline(sourceText: String, action: TextAction, actionNameOverride: String) async {
        workflowState = action.engine == .none ? .transcribing : .applyingAction

        var outputText = sourceText
        var metadata: [String: String] = [:]
        var effectiveActionName = actionNameOverride

        if action.engine != .none {
            statusMessage = "Выполняю действие: \(action.name)"
            cursorHUD.showPersistent(text: "Действие: \(short(action.name))", color: .systemOrange)
            do {
                let output = try await actionRunner.run(action: action, text: sourceText)
                outputText = output.text
                metadata = output.metadata
            } catch {
                outputText = sourceText
                effectiveActionName = "Без обработки (fallback)"
                lastErrorMessage = error.localizedDescription
                logger.warn("Action failed, fallback to transcript: \(error.localizedDescription)")
            }
        }

        let delivery = injector.deliver(outputText, mode: settingsStore.settings.outputMode)
        switch delivery {
        case .inserted(let appName):
            statusMessage = "Вставлено в \(appName)"
            notifier.send(title: "Local Kiklet", body: "Вставлено в \(appName)")
            cursorHUD.showTransient(text: "Вставлено в \(short(appName))", color: .systemGreen)
        case .copied:
            statusMessage = "Скопировано в буфер"
            notifier.send(title: "Local Kiklet", body: "Скопировано в буфер")
            cursorHUD.showTransient(text: "Скопировано в буфер", color: .systemGreen)
        }

        let historyItem = HistoryItem(
            actionName: effectiveActionName,
            transcription: sourceText,
            resultText: outputText,
            metadata: metadata
        )
        historyStore.add(historyItem, limit: settingsStore.settings.maxHistoryItems)

        workflowState = .idle
    }

    private func short(_ text: String, limit: Int = 42) -> String {
        if text.count <= limit { return text }
        return "\(text.prefix(limit - 1))…"
    }
}
