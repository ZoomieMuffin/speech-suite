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

    /// Push-to-Talk 中のオーバーレイ表示の有効/無効（既定: ON）
    public var overlayEnabled: Bool = true

    public init() {}

    // MARK: - Codable

    private enum CodingKeys: String, CodingKey {
        case insertHotkey
        case dailyVoiceNoteHotkey
        case notesDirPath
        case fillerFilterEnabled
        case fillerPatterns
        case overlayEnabled
    }

    /// カスタムデコーダー。
    /// 旧バージョンの JSON に `overlayEnabled` キーが存在しない場合に既定値 `true` を使う。
    /// これにより、アップグレード時に全設定がリセットされる問題を防ぐ。
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        insertHotkey         = try c.decode(HotkeyConfiguration.self, forKey: .insertHotkey)
        dailyVoiceNoteHotkey = try c.decode(HotkeyConfiguration.self, forKey: .dailyVoiceNoteHotkey)
        notesDirPath         = try c.decode(String.self,               forKey: .notesDirPath)
        fillerFilterEnabled  = try c.decode(Bool.self,                 forKey: .fillerFilterEnabled)
        fillerPatterns       = try c.decode([String].self,             forKey: .fillerPatterns)
        overlayEnabled       = try c.decodeIfPresent(Bool.self, forKey: .overlayEnabled) ?? true
    }
}

extension AppSettings {
    /// notesDirPath を展開した URL。チルダ展開を行う。
    public var notesDirURL: URL {
        URL(fileURLWithPath: (notesDirPath as NSString).expandingTildeInPath)
    }
}
