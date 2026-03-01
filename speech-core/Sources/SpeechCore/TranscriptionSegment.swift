import Foundation

/// 文字起こし結果の1セグメント。
public struct TranscriptionSegment: Sendable, Codable, Equatable {
    public let text: String
    public let startTime: TimeInterval
    public let endTime: TimeInterval
    public let confidence: Float?
    public let speaker: String?

    public var duration: TimeInterval { endTime - startTime }

    public init(
        text: String,
        startTime: TimeInterval,
        endTime: TimeInterval,
        confidence: Float? = nil,
        speaker: String? = nil
    ) throws(SpeechCoreError) {
        guard startTime.isFinite, endTime.isFinite else {
            throw SpeechCoreError.invalidTimeRange
        }
        guard startTime >= 0 else {
            throw SpeechCoreError.invalidTimeRange
        }
        guard endTime >= startTime else {
            throw SpeechCoreError.invalidTimeRange
        }
        guard (endTime - startTime).isFinite else {
            throw SpeechCoreError.invalidTimeRange
        }
        if let c = confidence {
            guard (0.0...1.0).contains(c) else {
                throw SpeechCoreError.invalidConfiguration("confidence must be in 0...1")
            }
        }
        self.text = text
        self.startTime = startTime
        self.endTime = endTime
        self.confidence = confidence
        self.speaker = speaker
    }
}
