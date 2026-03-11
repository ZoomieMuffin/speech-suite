import Foundation

/// AppSettings を UserDefaults に JSON で永続化するストア。
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
