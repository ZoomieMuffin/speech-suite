import AppKit
import SwiftUI

@main
struct AudioInputApp: App {
    @State private var appState = AppState()
    @State private var settingsStore = SettingsStore()
    @State private var notificationService = NotificationService()
    @State private var overlayController = OverlayWindowController()
    // TODO: AudioRecorderProtocol と TranscriptionService の具体実装が揃う PRV-72 で初期化する。
    @State private var controller: AppController?

    var body: some Scene {
        MenuBarExtra {
            MenuBarContentView(
                appState: appState,
                settingsStore: settingsStore,
                notificationService: notificationService,
                overlayController: overlayController
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
/// `.onChange` でオーバーレイの表示/非表示を制御する。
private struct MenuBarContentView: View {
    let appState: AppState
    let settingsStore: SettingsStore
    let notificationService: NotificationService
    let overlayController: OverlayWindowController

    var body: some View {
        Text(statusLabel)
            .foregroundStyle(.secondary)
            .task {
                await notificationService.requestAuthorization()
            }
            .onChange(of: appState.status) { _, newStatus in
                switch newStatus {
                case .recording, .transcribing:
                    if settingsStore.settings.overlayEnabled {
                        overlayController.show(appState: appState)
                    }
                case .idle, .error:
                    overlayController.hide()
                }
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
