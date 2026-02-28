import Foundation

/// Whisper 等が生成するハルシネーションセグメントを除去するフィルター。
/// Phase 2: 短セグメント（duration が閾値未満）を除外する。
public struct HallucinationFilter: Sendable {
    /// この秒数未満のセグメントを除外する（デフォルト 0.5秒）。
    public let minimumDuration: TimeInterval

    public init(minimumDuration: TimeInterval = 0.5) {
        self.minimumDuration = minimumDuration
    }

    public func filter(_ segments: [TranscriptionSegment]) -> [TranscriptionSegment] {
        segments.filter({ (s: TranscriptionSegment) in s.duration >= minimumDuration })
    }
}
