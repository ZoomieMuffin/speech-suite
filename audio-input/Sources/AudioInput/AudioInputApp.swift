import AppKit
import SwiftUI

@main
struct AudioInputApp: App {
    @State private var settingsStore = SettingsStore()
    @State private var notificationService = NotificationService()
    // TODO: AppController を初期化するには AudioRecorderProtocol と TranscriptionService の
    //       具体実装が必要（PRV-71, PRV-72 で実装予定）。
    @State private var controller: AppController?

    var body: some Scene {
        MenuBarExtra("AudioInput", systemImage: "mic") {
            Text("AudioInput")
                .task {
                    await notificationService.requestAuthorization()
                }
            Divider()
            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
        }
    }
}
