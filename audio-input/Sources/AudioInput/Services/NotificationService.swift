import Foundation
import UserNotifications

/// エラー発生時にシステム通知を表示するサービス。
@MainActor
public final class NotificationService {
    private var isAuthorized = false

    public init() {}

    /// 通知権限を要求する。初回起動時に呼ぶ。
    public func requestAuthorization() async {
        do {
            isAuthorized = try await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .sound])
        } catch {
            isAuthorized = false
        }
    }

    /// エラーをシステム通知で表示する。
    /// - Parameters:
    ///   - error: 表示するエラー
    ///   - context: 通知タイトル（例: "Voice Note 保存エラー"）
    public func notifyError(_ error: any Error, context: String) {
        guard isAuthorized else { return }
        let content = UNMutableNotificationContent()
        content.title = context
        content.body = error.localizedDescription
        content.sound = .default
        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }
}
