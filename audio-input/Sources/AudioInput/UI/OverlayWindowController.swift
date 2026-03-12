import AppKit
import SwiftUI

/// Push-to-Talk 録音中に表示するフローティングオーバーレイのウィンドウ管理。
///
/// `NSPanel` の `nonactivatingPanel` スタイルを使用し、フォーカスを奪わない。
/// パネルは初回 `show()` 時に一度だけ生成し、以降は表示/非表示を切り替える。
@MainActor
final class OverlayWindowController {
    private var panel: NSPanel?

    /// オーバーレイを表示する。
    /// - Parameter appState: OverlayView が購読する状態モデル。
    func show(appState: AppState) {
        if panel == nil {
            panel = makePanel(appState: appState)
        }
        panel?.orderFront(nil)
    }

    /// オーバーレイを非表示にする。
    func hide() {
        panel?.orderOut(nil)
    }

    // MARK: - Private

    private func makePanel(appState: AppState) -> NSPanel {
        let overlayView = OverlayView(appState: appState)
        let hostingView = NSHostingView(rootView: overlayView)
        hostingView.frame = NSRect(x: 0, y: 0, width: 240, height: 44)

        let newPanel = NSPanel(
            contentRect: hostingView.frame,
            styleMask: [.nonactivatingPanel, .hudWindow],
            backing: .buffered,
            defer: false
        )
        newPanel.contentView = hostingView
        newPanel.level = .floating
        newPanel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        newPanel.isMovableByWindowBackground = true
        newPanel.backgroundColor = .clear
        newPanel.hasShadow = false
        newPanel.isOpaque = false

        // メインスクリーン下部中央に配置
        if let screen = NSScreen.main {
            let x = screen.frame.midX - 120
            let y = screen.frame.minY + 80
            newPanel.setFrameOrigin(NSPoint(x: x, y: y))
        }
        return newPanel
    }
}
