import Foundation
import OSLog
import UserNotifications

/// エラー発生時にシステム通知を表示するサービス。
@MainActor
public final class NotificationService {
    private var isAuthorized = false
    private let logger = Logger(subsystem: "com.speech-suite.audio-input", category: "NotificationService")
    /// 進行中または完了済みの権限要求 Task。
    /// 複数の呼び出し元が同時に requestAuthorization() を呼んでも
    /// 実際のシステム API は一度だけ実行され、全呼び出し元が結果を共有する。
    private var authorizationTask: Task<Void, Never>?

    public init() {}

    /// 通知権限を要求する。
    /// 同時呼び出しや重複呼び出しに対して Task デデュプリケーションで対応する。
    /// 既存 Task が完了済みの場合は即座に return する。
    public func requestAuthorization() async {
        if let existing = authorizationTask {
            await existing.value
            return
        }
        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                isAuthorized = try await UNUserNotificationCenter.current()
                    .requestAuthorization(options: [.alert, .sound])
                if !isAuthorized {
                    // ユーザーが権限を拒否した場合。保存失敗等のエラーが通知できなくなる。
                    logger.warning("Notification authorization denied by user — error notifications will be suppressed.")
                }
            } catch {
                isAuthorized = false
                logger.error("Notification authorization request failed: \(error.localizedDescription, privacy: .public)")
            }
        }
        authorizationTask = task
        await task.value
    }

    /// エラーをシステム通知で表示する。
    /// - Parameters:
    ///   - error: 表示するエラー
    ///   - context: 通知タイトル（例: "Voice Note 保存エラー"）
    public func notifyError(_ error: any Error, context: String) {
        guard isAuthorized else {
            logger.warning("Cannot deliver notification (not authorized) — context: \(context, privacy: .public), error: \(error.localizedDescription, privacy: .public)")
            return
        }
        let content = UNMutableNotificationContent()
        content.title = context
        content.body = error.localizedDescription
        content.sound = .default
        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request) { [logger] deliveryError in
            // 通知配信失敗を通知で伝えることはできないため、システムログに記録する。
            if let deliveryError {
                logger.error("Failed to schedule notification — context: \(context, privacy: .public), error: \(deliveryError.localizedDescription, privacy: .public)")
                assertionFailure("NotificationService: failed to schedule notification: \(deliveryError)")
            }
        }
    }
}
