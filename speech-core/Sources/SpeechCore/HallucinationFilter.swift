import Foundation

/// Whisper 等が生成するハルシネーションセグメントを除去するフィルター。
/// 短セグメント（duration ベース）と既知のハルシネーション文字列（content ベース）の両方を除外する。
public struct HallucinationFilter: Sendable {
    /// この秒数未満のセグメントを除外する（デフォルト 0.5秒）。
    public let minimumDuration: TimeInterval

    /// 既知のハルシネーションパターン（完全一致、トリム後）。
    private static let knownHallucinations: [String] = [
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
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        let lowercased = trimmed.lowercased()
        return Self.knownHallucinations.contains { pattern in
            lowercased == pattern.lowercased()
        }
    }
}
