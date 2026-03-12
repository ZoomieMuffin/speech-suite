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
        // orderFrontRegardless() はアプリが非アクティブな状態でも前面に表示する。
        // グローバルホットキーで別アプリ操作中に起動する要件に必須。
        panel?.orderFrontRegardless()
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
        // アプリ非アクティブ時にパネルが自動的に隠れないようにする。
        // グローバルホットキー操作中は常に別アプリがアクティブなため必須。
        newPanel.hidesOnDeactivate = false
        return newPanel
    }

    /// show() のたびに呼び出してスクリーン位置を更新する。
    /// visibleFrame ベースで Dock / メニューバーとの重なりを回避する。
    ///
    /// スクリーン解決の優先順位:
    /// 1. NSEvent.mouseLocation を含む画面（ホットキー押下時はカーソル位置が最も自然）
    /// 2. NSScreen.main（フォールバック）
    /// 3. NSScreen.screens.first（さらなるフォールバック）
    /// いずれも nil / 空の場合は配置をスキップする（(0,0) への誤配置を防ぐ）。
    private func repositionIfNeeded() {
        guard let panel else { return }
        let cursor = NSEvent.mouseLocation
        let screen =
            NSScreen.screens.first(where: { $0.frame.contains(cursor) })
            ?? NSScreen.main
            ?? NSScreen.screens.first
        guard let screen else { return }
        let x = screen.visibleFrame.midX - panel.frame.width / 2
        let y = screen.visibleFrame.minY + 16
        panel.setFrameOrigin(NSPoint(x: x, y: y))
    }
}
