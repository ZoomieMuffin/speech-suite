import Foundation

/// Whisper 等が生成するハルシネーションセグメントを除去するフィルター。
/// 短セグメント（duration ベース）と既知のハルシネーション文字列（content ベース）の両方を除外する。
public struct HallucinationFilter: Sendable {
    /// この秒数未満のセグメントを除外する（デフォルト 0.5秒）。
    public let minimumDuration: TimeInterval

    /// ユーザー定義の正規化済みフィラーパターン。
    private let normalizedCustomPatterns: Set<String>

    /// 正規化後の最長パターン文字数。正規化後にこれを超える入力は Set lookup を省略する。
    /// 組み込みパターンとカスタムパターンのうち長い方。
    private let maxPatternLength: Int

    /// 組み込みパターン専用の最長文字数（static キャッシュ）。
    private static let staticMaxPatternLength: Int = {
        normalizedHallucinations.map(\.count).max() ?? 0
    }()

    /// 除去対象の文字セット（句読点 + 記号 + 結合文字 + 非空白制御文字）。
    /// 結合文字（variation selector 等）はロケール固定の folding では除去されないため明示的に含める。
    private static let removableCharacters: CharacterSet = {
        var cs = CharacterSet.punctuationCharacters
        cs.formUnion(.symbols)
        cs.formUnion(.nonBaseCharacters)
        cs.formUnion(CharacterSet.controlCharacters.subtracting(.whitespacesAndNewlines))
        return cs
    }()

    /// デフォルト設定のフィルターインスタンス。init が throws のためデフォルト引数で使用する。
    public static let `default`: HallucinationFilter? = try? HallucinationFilter()

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

    /// - Parameters:
    ///   - minimumDuration: この秒数未満のセグメントを除外する（デフォルト 0.5秒）。
    ///   - customPatterns: ユーザー定義のフィラーパターン。正規化後に完全一致で除去する。
    public init(minimumDuration: TimeInterval = 0.5, customPatterns: [String] = []) throws(SpeechCoreError) {
        guard minimumDuration >= 0, minimumDuration.isFinite else {
            throw SpeechCoreError.invalidConfiguration("minimumDuration must be >= 0 and finite")
        }
        self.minimumDuration = minimumDuration
        let normalized = Set(customPatterns.map { Self.normalize($0) }.filter { !$0.isEmpty })
        self.normalizedCustomPatterns = normalized
        let customMax = normalized.map(\.count).max() ?? 0
        self.maxPatternLength = max(Self.staticMaxPatternLength, customMax)
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
        if normalized.count > maxPatternLength { return false }
        return Self.normalizedHallucinations.contains(normalized)
            || normalizedCustomPatterns.contains(normalized)
    }

    /// Unicode 正規化（NFKC）+ 大文字小文字/全角半角の統一 + 句読点・記号除去 + 内部空白圧縮。
    private static func normalize(_ text: String) -> String {
        // NFKC: 全角英数→半角、合字分解、互換文字統一
        let nfkc = text.precomposedStringWithCompatibilityMapping
        // case fold + diacritic strip
        let folded = nfkc.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: Locale(identifier: "en_US_POSIX"))
        // 句読点・記号（emoji 含む）を除去
        let stripped = folded.unicodeScalars.filter { !removableCharacters.contains($0) }
        let result = String(String.UnicodeScalarView(stripped))
        // 空白を全除去（空白混入によるすり抜けを防止）
        let compressed = result.unicodeScalars.filter { !CharacterSet.whitespacesAndNewlines.contains($0) }
        return String(String.UnicodeScalarView(compressed))
    }
}
