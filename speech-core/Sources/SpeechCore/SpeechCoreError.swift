/// SpeechCore で発生するエラー。
public enum SpeechCoreError: Error, Equatable, Sendable {
    case fileNotFound
    case unsupportedFormat
    case transcriptionFailed(String)
    case invalidTimeRange
    case invalidConfiguration(String)
    /// start() を既に開始済みの状態で再呼び出しした場合。
    case alreadyStarted
}
