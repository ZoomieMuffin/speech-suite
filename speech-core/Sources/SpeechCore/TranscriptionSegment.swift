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

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let text = try container.decode(String.self, forKey: .text)
        let startTime = try container.decode(TimeInterval.self, forKey: .startTime)
        let endTime = try container.decode(TimeInterval.self, forKey: .endTime)
        let confidence = try container.decodeIfPresent(Float.self, forKey: .confidence)
        let speaker = try container.decodeIfPresent(String.self, forKey: .speaker)
        do {
            try self.init(
                text: text,
                startTime: startTime,
                endTime: endTime,
                confidence: confidence,
                speaker: speaker
            )
        } catch {
            throw DecodingError.dataCorrupted(
                .init(codingPath: decoder.codingPath, debugDescription: "\(error)")
            )
        }
    }
}
