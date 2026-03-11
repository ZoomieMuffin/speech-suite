import Foundation

/// ホットキーイベントのコールバック。
public enum HotkeyEvent: Sendable {
    case pressed
    case released
}

/// グローバルホットキーの監視を抽象化するプロトコル。
/// modifier-only（右 Option 単体）と通常キーコンボの両方を扱う。
/// AppKit イベント監視を前提とするため @MainActor に制約する。
@MainActor
public protocol HotkeyManagerProtocol: Sendable {
    /// ホットキー監視を開始する。イベントは handler 経由で通知。
    /// handler は MainActor 上で呼び出されることを保証する。
    func start(handler: @escaping @MainActor (HotkeyEvent) async -> Void) async throws
    /// ホットキー監視を停止する。
    func stop() async
}
