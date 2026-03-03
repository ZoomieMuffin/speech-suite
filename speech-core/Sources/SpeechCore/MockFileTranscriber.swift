import Foundation

public struct MockFileTranscriber: FileTranscriberProtocol {
    private let segments: [TranscriptionSegment]
    private let error: (any Error & Sendable)?

    public init(segments: [TranscriptionSegment], error: (any Error & Sendable)? = nil) {
        self.segments = segments
        self.error = error
    }

    public func transcribe(fileURL: URL, locale: Locale) -> AsyncThrowingStream<TranscriptionSegment, Error> {
        let segments = self.segments
        let error = self.error
        return AsyncThrowingStream { continuation in
            guard fileURL.isFileURL else {
                continuation.finish(throwing: SpeechCoreError.invalidInputURL)
                return
            }
            for segment in segments {
                continuation.yield(segment)
            }
            if let error {
                continuation.finish(throwing: error)
            } else {
                continuation.finish()
            }
        }
    }
}
