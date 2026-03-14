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

    private static let delimiters = CharacterSet(charactersIn: "、。,.!?")

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
        // ゼロ幅アサーションでフィラー本体のみを除去し、句読点は後処理で正規化する。
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
        return normalize(result)
    }

    /// フィラー除去後の残骸（連続句読点・先頭末尾の句読点・余分な空白）を正規化する。
    ///
    /// ゼロ幅境界でフィラー本体だけを消すと句読点が孤立する。
    /// - "、今日は"        → "今日は"（先頭句読点を除去）
    /// - "今日は、、会議"  → "今日は、会議"（連続句読点を圧縮）
    /// - "今日は、"        → "今日は"（末尾句読点を除去）
    private func normalize(_ text: String) -> String {
        // 1. 句読点 [空白*句読点]* のランを先頭の 1 文字に圧縮
        var collapsed = ""
        var i = text.startIndex
        while i < text.endIndex {
            if isDelimiter(text[i]) {
                collapsed.append(text[i])
                var j = text.index(after: i)
                while j < text.endIndex, isDelimiter(text[j]) || text[j].isWhitespace {
                    j = text.index(after: j)
                }
                i = j
            } else {
                collapsed.append(text[i])
                i = text.index(after: i)
            }
        }

        // 2. 先頭の句読点 + 空白を除去
        var start = collapsed.startIndex
        while start < collapsed.endIndex, isDelimiter(collapsed[start]) || collapsed[start].isWhitespace {
            start = collapsed.index(after: start)
        }

        // 3. 末尾の句読点 + 空白を除去
        var end = collapsed.endIndex
        while end > start {
            let prev = collapsed.index(before: end)
            if isDelimiter(collapsed[prev]) || collapsed[prev].isWhitespace {
                end = prev
            } else {
                break
            }
        }

        // 4. 内部の連続空白を正規化
        return String(collapsed[start..<end])
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    private func isDelimiter(_ c: Character) -> Bool {
        c.unicodeScalars.allSatisfy { Self.delimiters.contains($0) }
    }
}
