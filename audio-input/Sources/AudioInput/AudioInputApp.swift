import SwiftUI

@main
struct AudioInputApp: App {
    var body: some Scene {
        MenuBarExtra("AudioInput", systemImage: "mic") {
            Text("AudioInput")
            Divider()
            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
        }
    }
}
