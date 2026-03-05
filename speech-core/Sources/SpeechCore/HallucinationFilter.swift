import Foundation

/// Whisper 等が生成するハルシネーションセグメントを除去するフィルター。
/// 短セグメント（duration ベース）と既知のハルシネーション文字列（content ベース）の両方を除外する。
public struct HallucinationFilter: Sendable {
    /// この秒数未満のセグメントを除外する（デフォルト 0.5秒）。
    public let minimumDuration: TimeInterval

    /// 正規化後の最長パターン文字数。これより長い入力は normalize をスキップできる。
    private static let maxPatternLength: Int = {
        normalizedHallucinations.map(\.count).max() ?? 0
    }()

    /// 事前正規化済みのハルシネーションパターン Set（O(1) 判定）。
    /// 完全一致で判定する（部分一致にすると通常発話の誤検知リスクが高い）。
    private static let normalizedHallucinations: Set<String> = {
        let patterns = [
            // Japanese
            "ご視聴ありがとうございました",
            "チャンネル登録よろしくお願いします",
            "いいねとチャンネル登録お願いします",
            "チャンネル登録お願いします",
            "高評価お願いします",
            "ご視聴ありがとうございます",
            // English
            "Thank you for watching",
            "Thanks for watching",
            "Please subscribe",
            "Like and subscribe",
        ]
        return Set(patterns.map { normalize($0) })
    }()

    public init(minimumDuration: TimeInterval = 0.5) throws(SpeechCoreError) {
        guard minimumDuration >= 0, minimumDuration.isFinite else {
            throw SpeechCoreError.invalidConfiguration("minimumDuration must be >= 0 and finite")
        }
        self.minimumDuration = minimumDuration
    }

    public func filter(_ segments: [TranscriptionSegment]) -> [TranscriptionSegment] {
        segments.filter { s in
            s.duration >= minimumDuration && !isHallucination(s.text)
        }
    }

    private func isHallucination(_ text: String) -> Bool {
        let normalized = Self.normalize(text)
        guard !normalized.isEmpty else { return false }
        // 正規化後の長さが最長パターンを超えていればマッチしない
        if normalized.count > Self.maxPatternLength { return false }
        return Self.normalizedHallucinations.contains(normalized)
    }

    /// Unicode 正規化（NFKC）+ 大文字小文字/全角半角の統一 + 句読点除去 + 内部空白圧縮。
    private static func normalize(_ text: String) -> String {
        // NFKC: 全角英数→半角、合字分解、互換文字統一
        let nfkc = text.precomposedStringWithCompatibilityMapping
        // case fold + diacritic strip
        let folded = nfkc.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil)
        // 句読点・記号を除去（Unicode カテゴリ P: Punctuation）
        let stripped = folded.unicodeScalars.filter { !CharacterSet.punctuationCharacters.contains($0) }
        let result = String(String.UnicodeScalarView(stripped))
        // 連続空白（改行・タブ・全角空白含む）を単一スペースに圧縮
        let compressed = result.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        return compressed
    }
}
