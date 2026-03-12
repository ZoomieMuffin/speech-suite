import AppKit
import SwiftUI

@main
struct AudioInputApp: App {
    @State private var appState = AppState()
    @State private var settingsStore = SettingsStore()
    @State private var notificationService = NotificationService()
    @State private var overlayController = OverlayWindowController()
    // TODO: AudioRecorderProtocol と TranscriptionService の具体実装が揃う PRV-72 で初期化する。
    //       初期化例:
    //         controller = try? AppController(
    //             settingsStore: settingsStore,
    //             notificationService: notificationService,
    //             appState: appState,
    //             overlayController: overlayController,
    //             recorder: <AudioRecorderProtocol実装>,
    //             transcriptionService: <TranscriptionService実装>,
    //             inserter: <TextInserterProtocol実装>
    //         )
    //       AppController が nil の間、アイコンは .idle 固定でオーバーレイは表示されない。
    @State private var controller: AppController?

    var body: some Scene {
        MenuBarExtra {
            MenuBarContentView(
                appState: appState,
                notificationService: notificationService
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
    let notificationService: NotificationService

    var body: some View {
        Text(statusLabel)
            .foregroundStyle(.secondary)
            .task {
                await notificationService.requestAuthorization()
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
