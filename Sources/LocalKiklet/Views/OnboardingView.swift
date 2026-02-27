import SwiftUI

struct OnboardingView: View {
    @ObservedObject var model: AppViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Добро пожаловать в Local Kiklet")
                .font(.title2)
                .bold()

            Text("Выдайте разрешения и при необходимости добавьте API-ключ для действий OpenAI.")
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 8) {
                ForEach(PermissionKind.allCases) { kind in
                    HStack {
                        Image(systemName: model.permissionManager.status(for: kind) ? "checkmark.circle.fill" : "xmark.circle")
                            .foregroundStyle(model.permissionManager.status(for: kind) ? .green : .red)
                        VStack(alignment: .leading) {
                            Text(kind.title).bold()
                            Text(kind.subtitle)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Запросить") {
                            model.requestPermission(kind)
                        }
                        Button("Открыть настройки") {
                            model.openPermissionSettings(kind)
                        }
                    }
                    .padding(.vertical, 2)
                }

                Button("Запросить все разрешения") {
                    model.requestAllMissingPermissions()
                }

                Button("Проверить разрешения") {
                    model.checkPermissions()
                    model.restartHotkeys()
                }

                Button("Скопировать путь app") {
                    model.copyCurrentAppPath()
                }

                Button("Показать app в Finder") {
                    model.revealCurrentAppInFinder()
                }

                if let permissionsStatus = model.permissionsStatusMessage {
                    Text(permissionsStatus)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if let hotkeyHint = model.hotkeyRequirementsMessage {
                    Text(hotkeyHint)
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                Text("Локальный Whisper")
                    .bold()
                Text(model.localEngineStatusMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                HStack {
                    Button(model.isInstallingLocalEngine ? "Устанавливаю..." : "Установить автоматически") {
                        model.installLocalEngine()
                    }
                    .disabled(model.isInstallingLocalEngine)

                    Button("Проверить") {
                        model.refreshLocalEngineStatus()
                    }
                    .disabled(model.isInstallingLocalEngine)
                }
            }

            Divider()

            VStack(alignment: .leading, spacing: 6) {
                Text("OpenAI API-ключ (опционально)")
                    .bold()
                SecureField("sk-...", text: $model.apiKeyFieldValue)
                HStack {
                    Button("Сохранить") { model.saveAPIKey() }
                    Button("Проверить") { model.verifyAPIKey() }
                    if let apiStatus = model.apiKeyStatusMessage {
                        Text(apiStatus)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Spacer()

            HStack {
                Spacer()
                Button("Завершить") {
                    model.completeOnboarding()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(minWidth: 680, minHeight: 420)
    }
}
