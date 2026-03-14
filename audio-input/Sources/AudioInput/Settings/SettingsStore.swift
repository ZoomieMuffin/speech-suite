import Foundation
import Observation

/// `AppSettings` を UserDefaults に JSON で永続化する Observable ストア。
///
/// `@Observable` により `settings` の変更が SwiftUI の再描画を自動駆動する。
/// 実行中の UserDefaults 変更は `update(_:)` 経由でのみ反映され、
/// 外部（他プロセス・Settings UI）からの変更は次回起動まで反映されない。
@MainActor
@Observable
public final class SettingsStore {
    static let userDefaultsKey = "com.speech-suite.AppSettings"

    public private(set) var settings: AppSettings

    public init() {
        if let data = UserDefaults.standard.data(forKey: Self.userDefaultsKey) {
            if let decoded = try? JSONDecoder().decode(AppSettings.self, from: data) {
                self.settings = decoded
            } else {
                // JSON 不整合または schema 変更により復元に失敗。デフォルト値で起動する。
                // ホットキーや保存先が静かに失われるリスクがあるため、デバッグビルドで検出する。
                assertionFailure(
                    "SettingsStore: failed to decode AppSettings from UserDefaults. Starting with defaults."
                )
                self.settings = AppSettings()
            }
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
