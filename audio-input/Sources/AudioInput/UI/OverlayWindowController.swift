import AppKit
import SwiftUI

/// Push-to-Talk 録音中に表示するフローティングオーバーレイのウィンドウ管理。
///
/// `NSPanel` の `nonactivatingPanel` スタイルを使用し、フォーカスを奪わない。
/// パネルは初回 `show()` 時に一度だけ生成し、以降は表示/非表示を切り替える。
@MainActor
public final class OverlayWindowController {
    private var panel: NSPanel?

    public init() {}

    /// オーバーレイを表示する。
    /// show() のたびにスクリーンを再解決して位置を更新するため、
    /// マルチディスプレイ切り替え後や NSScreen.main が初回 nil だった場合も正しく配置される。
    /// - Parameter appState: OverlayView が購読する状態モデル。
    public func show(appState: AppState) {
        if panel == nil {
            panel = makePanel(appState: appState)
        }
        repositionIfNeeded()
        panel?.orderFront(nil)
    }

    /// オーバーレイを非表示にする。
    public func hide() {
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
        newPanel.backgroundColor = .clear
        newPanel.hasShadow = false
        newPanel.isOpaque = false
        return newPanel
    }

    /// show() のたびに呼び出してスクリーン位置を更新する。
    /// NSScreen.main を毎回解決するため、マルチディスプレイ切り替えにも対応する。
    /// visibleFrame ベースで Dock / メニューバーとの重なりを回避する。
    private func repositionIfNeeded() {
        guard let panel, let screen = NSScreen.main else { return }
        let x = screen.visibleFrame.midX - panel.frame.width / 2
        let y = screen.visibleFrame.minY + 16
        panel.setFrameOrigin(NSPoint(x: x, y: y))
    }
}
