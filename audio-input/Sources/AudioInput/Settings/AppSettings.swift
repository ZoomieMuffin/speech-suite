import Foundation

/// アプリ全体の設定を保持する値型。UserDefaults に JSON で永続化する。
public struct AppSettings: Codable, Sendable, Equatable {
    /// Insert モードのホットキー（右 Option ホールド）
    public var insertHotkey: HotkeyConfiguration = .rightOption

    /// Daily Voice Note モードのホットキー（Shift+Ctrl+F ホールド）
    public var dailyVoiceNoteHotkey: HotkeyConfiguration = .shiftControlF

    /// Voice Note の保存先ディレクトリ（チルダ展開可能なパス文字列）
    public var notesDirPath: String = "~/audio"

    /// フィラー除去フィルタの有効/無効
    public var fillerFilterEnabled: Bool = true

    /// ユーザー定義のフィラーパターン（完全一致、正規化後に比較）
    public var fillerPatterns: [String] = []

    public init() {}
}

extension AppSettings {
    /// notesDirPath を展開した URL。チルダ展開を行う。
    public var notesDirURL: URL {
        URL(fileURLWithPath: (notesDirPath as NSString).expandingTildeInPath)
    }
}
