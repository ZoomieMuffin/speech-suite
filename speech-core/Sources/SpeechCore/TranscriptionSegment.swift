import Foundation

/// 文字起こし結果の1セグメント。
public struct TranscriptionSegment: Sendable {
    public let text: String
    public let startTime: TimeInterval
    public let endTime: TimeInterval
    public let confidence: Float?

    public var duration: TimeInterval { endTime - startTime }

    public init(
        text: String,
        startTime: TimeInterval,
        endTime: TimeInterval,
        confidence: Float? = nil
    ) {
        precondition(endTime >= startTime, "endTime must be >= startTime")
        self.text = text
        self.startTime = startTime
        self.endTime = endTime
        self.confidence = confidence
    }
}
