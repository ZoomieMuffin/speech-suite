import Foundation

/// 文字起こしテキストからフィラー（「えーと」「あの」等）を除去するプロセッサ。
///
/// 組み込み辞書とユーザー定義パターンの両方に対応する。
/// 前後の区切り文字（空白・句読点・文頭/文末）で境界判定し、部分一致による誤除去を防ぐ。
public struct FillerTextProcessor: TextProcessorProtocol, Sendable {
    private let pattern: NSRegularExpression?

    /// 組み込みの日本語フィラー。長い順に並べてマッチ優先度を制御する。
    static let builtInJapanese: [String] = [
        "えーっと", "えーと", "えっと", "ええと",
        "えー", "えぇ",
        "あのー", "あのう", "あの",
        "そのー", "そのう",
        "うーんと", "うーん",
        "まあ", "まぁ",
        "なんか",
        "こう",
        "ほら",
        "そうですね",
    ]

    /// 組み込みの英語フィラー。
    static let builtInEnglish: [String] = [
        "you know",
        "I mean",
        "uh huh",
        "um", "uh",
        "hmm",
    ]

    /// - Parameter customPatterns: ユーザー定義のフィラーパターン。空の場合は組み込み辞書のみ使用する。
    public init(customPatterns: [String] = []) {
        let allPatterns = Self.builtInJapanese + Self.builtInEnglish + customPatterns
        let escaped = allPatterns
            .filter { !$0.isEmpty }
            .sorted { $0.count > $1.count }
            .map { NSRegularExpression.escapedPattern(for: $0) }

        guard !escaped.isEmpty else {
            self.pattern = nil
            return
        }

        // 日本語は \b が効かないため、前後の境界を区切り文字で判定する。
        let boundary = "(?:^|(?<=\\s|[、。,.!?]))"
        let trailingBoundary = "(?:$|(?=\\s|[、。,.!?]))"
        let alternatives = escaped.joined(separator: "|")
        let regex = "\(boundary)(?:\(alternatives))\(trailingBoundary)"
        self.pattern = try? NSRegularExpression(pattern: regex, options: [.caseInsensitive])
    }

    public func process(_ text: String) async throws -> String {
        guard let pattern else { return text }
        let range = NSRange(text.startIndex..., in: text)
        let result = pattern.stringByReplacingMatches(in: text, range: range, withTemplate: "")
        return normalizeWhitespace(result)
    }

    /// 除去後に残る連続空白・先頭末尾空白を正規化する。
    private func normalizeWhitespace(_ text: String) -> String {
        let components = text.components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
        return components.joined(separator: " ")
    }
}
