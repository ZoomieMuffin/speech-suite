import Foundation

public struct MockFileTranscriber: FileTranscriberProtocol {
    private let segments: [TranscriptionSegment]

    public init(segments: [TranscriptionSegment]) {
        self.segments = segments
    }

    public func transcribe(fileURL: URL, locale: Locale) -> AsyncThrowingStream<TranscriptionSegment, Error> {
        let segments = self.segments
        return AsyncThrowingStream { continuation in
            for segment in segments {
                continuation.yield(segment)
            }
            continuation.finish()
        }
    }
}
