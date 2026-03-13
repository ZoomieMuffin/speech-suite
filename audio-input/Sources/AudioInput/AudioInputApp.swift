import AppKit
import SwiftUI
import SpeechCore

@main
struct AudioInputApp: App {
    @State private var appState = AppState()
    @State private var settingsStore = SettingsStore()
    @State private var notificationService = NotificationService()
    @State private var overlayController = OverlayWindowController()
    @State private var registry = TranscriberRegistry()
    // TODO: AudioRecorderProtocol の具体実装が揃ったタイミングで AppController を初期化する。
    //       初期化例:
    //         controller = try? AppController(
    //             settingsStore: settingsStore,
    //             notificationService: notificationService,
    //             appState: appState,
    //             overlayController: overlayController,
    //             recorder: <AudioRecorderProtocol実装>,
    //             transcriptionService: <registry から取得した TranscriptionService>,
    //             inserter: <TextInserterProtocol実装>
    //         )
    //       AppController が nil の間、アイコンは .idle 固定でオーバーレイは表示されない。
    @State private var controller: AppController?

    var body: some Scene {
        MenuBarExtra {
            MenuBarContentView(
                appState: appState,
                settingsStore: settingsStore,
                notificationService: notificationService,
                registry: registry
            )
        } label: {
            MenuBarIconView(status: appState.status)
        }
    }
}

// MARK: - MenuBarIconView

/// メニューバーアイコン。録音状態に応じてアイコンを切り替える。
private struct MenuBarIconView: View {
    let status: AppState.Status

    var body: some View {
        Image(systemName: iconName)
            .symbolRenderingMode(.monochrome)
    }

    private var iconName: String {
        switch status {
        case .idle:         return "mic"
        case .recording:    return "mic.fill"
        case .transcribing: return "ellipsis"
        case .error:        return "exclamationmark.triangle.fill"
        }
    }
}

// MARK: - MenuBarContentView

/// メニューバーメニューのコンテンツ。
/// オーバーレイ表示制御は AppController.updateStatus(_:) が担うため、
/// View のライフサイクル（メニュー開閉）に依存しない。
private struct MenuBarContentView: View {
    let appState: AppState
    let settingsStore: SettingsStore
    let notificationService: NotificationService
    let registry: TranscriberRegistry

    @State private var availableServices: [any TranscriptionService] = []

    var body: some View {
        Text(statusLabel)
            .foregroundStyle(.secondary)
            .task {
                await notificationService.requestAuthorization()
                // macOS 26+ で SpeechAnalyzerTranscriber をレジストリに登録する。
                // 低バージョンでは if #available ガードにより実行されない。
                if #available(macOS 26, *) {
                    await registry.register(SpeechAnalyzerTranscriber(locale: .current))
                }
                availableServices = await registry.availableServices()
            }

        // macOS 26 以降で利用可能なサービスがある場合のみプロバイダ選択 UI を表示する。
        if #available(macOS 26, *), !availableServices.isEmpty {
            Divider()
            ProviderPickerView(
                settingsStore: settingsStore,
                services: availableServices
            )
        }

        Divider()
        Button("Quit") {
            NSApplication.shared.terminate(nil)
        }
        .keyboardShortcut("q")
    }

    private var statusLabel: String {
        switch appState.status {
        case .idle:                   return "Idle"
        case .recording(.insert):     return "Recording (Insert)"
        case .recording(.dvn):        return "Recording (Voice Note)"
        case .transcribing(.insert):  return "Transcribing (Insert)"
        case .transcribing(.dvn):     return "Transcribing (Voice Note)"
        case .error:                  return "Error"
        }
    }
}

// MARK: - ProviderPickerView

/// 利用可能な文字起こしプロバイダの一覧と選択 UI。macOS 26 以降でのみ表示される。
@available(macOS 26, *)
private struct ProviderPickerView: View {
    let settingsStore: SettingsStore
    let services: [any TranscriptionService]

    var body: some View {
        // nonisolated な id を同期アクセスで収集し、ForEach に String 配列を渡す。
        // existential key path (\.id) を避けることで Swift 6 の制約を回避する。
        let serviceIds = services.map { $0.id }
        ForEach(serviceIds, id: \.self) { serviceId in
            Button {
                settingsStore.update { $0.selectedTranscriptionServiceId = serviceId }
            } label: {
                HStack {
                    Text(displayName(for: serviceId))
                    Spacer()
                    if settingsStore.settings.selectedTranscriptionServiceId == serviceId {
                        Image(systemName: "checkmark")
                    }
                }
            }
        }
    }

    private func displayName(for id: String) -> String {
        switch id {
        case "com.speech-suite.speech-analyzer": return "Apple SpeechAnalyzer"
        default: return id
        }
    }
}
