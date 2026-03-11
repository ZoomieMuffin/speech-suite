import Foundation

/// AppSettings を UserDefaults に JSON で永続化するストア。
///
/// **設計上の制約（既知）**: 設定はインスタンス生成時に一度だけ読み込むスナップショット方式。
/// 実行中の UserDefaults 変更は `update(_:)` 経由でのみ反映され、
/// 外部（他プロセス・Settings UI）からの変更は次回起動まで反映されない。
/// 設定 UI 追加時に KVO / NotificationCenter ベースの live-update 対応を行う予定。
@MainActor
public final class SettingsStore {
    private static let userDefaultsKey = "com.speech-suite.AppSettings"

    public private(set) var settings: AppSettings

    public init() {
        if let data = UserDefaults.standard.data(forKey: Self.userDefaultsKey),
            let decoded = try? JSONDecoder().decode(AppSettings.self, from: data)
        {
            self.settings = decoded
        } else {
            self.settings = AppSettings()
        }
    }

    /// 設定を変更して永続化する。
    public func update(_ block: (inout AppSettings) -> Void) {
        block(&settings)
        save()
    }

    private func save() {
        if let data = try? JSONEncoder().encode(settings) {
            UserDefaults.standard.set(data, forKey: Self.userDefaultsKey)
        }
    }
}
