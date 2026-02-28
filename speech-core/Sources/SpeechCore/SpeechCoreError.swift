/// SpeechCore で発生するエラー。
public enum SpeechCoreError: Error, Equatable, Sendable {
    case fileNotFound
    case unsupportedFormat
    case transcriptionFailed(String)
    case invalidTimeRange
    case invalidConfiguration(String)
}
